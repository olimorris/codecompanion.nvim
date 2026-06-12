local Curl = require("plenary.curl")

local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local M = {}

---@class CopilotToken
---@field endpoints { api: string, ["origin-tracker"]: string, proxy: string, telemetry: string }
---@field expires_at number
---@field token string -- The actual token we use in our requests

---@alias CopilotOAuthToken string|nil
M._oauth_token = nil

---@type CopilotToken|nil
M._copilot_token = nil

-- Lock to prevent concurrent token requests
local _token_fetch_in_progress = false
local _token_wait_timeout = 5000 -- ms
local _token_wait_interval = 50 -- ms

---Finds the path where the token is stored
---@return string|nil
local function find_config_path()
  if os.getenv("CODECOMPANION_TOKEN_PATH") then
    return os.getenv("CODECOMPANION_TOKEN_PATH")
  end

  local path = vim.fs.normalize("$XDG_CONFIG_HOME")

  if path and vim.fn.isdirectory(path) > 0 then
    return path
  elseif vim.fn.has("win32") > 0 then
    path = vim.fs.normalize("~/AppData/Local")
    if vim.fn.isdirectory(path) > 0 then
      return path
    end
  else
    path = vim.fs.normalize("~/.config")
    if vim.fn.isdirectory(path) > 0 then
      return path
    end
  end
end

---Tries to retrieve the GitHub OAuth token from the user's disk
---@return CopilotOAuthToken
local function get_oauth_token()
  if M._oauth_token then
    return M._oauth_token
  end

  local token = os.getenv("GITHUB_TOKEN")
  local codespaces = os.getenv("CODESPACES")
  if token and codespaces then
    return token
  end

  local config_path = find_config_path()
  if not config_path then
    return nil
  end

  --- 1. Try searching the JSON files for the token

  local file_paths = {
    vim.fs.joinpath(config_path, "github-copilot", "hosts.json"),
    vim.fs.joinpath(config_path, "github-copilot", "apps.json"),
  }

  for _, file_path in ipairs(file_paths) do
    if vim.uv.fs_stat(file_path) then
      local ok, userdata = pcall(files.read, file_path)
      if not ok then
        log:error("Copilot Adapter: Could not read token from %s: %s", file_path, userdata)
        return nil
      end

      if vim.islist(userdata) then
        userdata = table.concat(userdata, " ")
      end

      userdata = vim.json.decode(userdata)
      for key, value in pairs(userdata) do
        if string.find(key, "github.com") then
          return value.oauth_token
        end
      end
    end
  end

  -- 2. Then try quering the SQLite database

  local db_path = vim.fs.joinpath(config_path, "github-copilot", "auth.db")
  if vim.uv.fs_stat(db_path) and vim.fn.executable("sqlite3") then
    local db_token
    vim
      .system(
        { "sqlite3", db_path, "SELECT token_ciphertext FROM oauth_tokens WHERE auth_authority == 'github.com' LIMIT 1" },
        { text = true },
        function(obj)
          db_token = vim.trim(obj.stdout)
        end
      )
      :wait()

    if db_token and db_token ~= "" then
      return db_token
    end
  end

  return nil
end

---Get a GitHub Copilot token using the OAuth token
---@return CopilotToken|nil
local function get_copilot_token()
  if M._copilot_token and M._copilot_token.expires_at and M._copilot_token.expires_at > os.time() then
    log:trace("Copilot Adapter: Reusing GitHub Copilot token")
    return M._copilot_token
  end

  -- If another fetch is in progress, wait and prevent multiple requests
  if _token_fetch_in_progress then
    local ok = vim.wait(_token_wait_timeout, function()
      return M._copilot_token and M._copilot_token.expires_at and M._copilot_token.expires_at > os.time()
    end, _token_wait_interval)
    if ok then
      log:trace("Copilot Adapter: Using token fetched by concurrent request")
      return M._copilot_token
    end
  end

  _token_fetch_in_progress = true
  log:trace("Authorizing GitHub Copilot token")

  local ok, request = pcall(function()
    return Curl.get("https://api.github.com/copilot_internal/v2/token", {
      headers = {
        Authorization = "Bearer " .. (M._oauth_token or ""),
        Accept = "application/json",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      on_error = function(err)
        vim.schedule(function()
          log:error("Copilot Adapter: Token request error %s", err)
        end)
      end,
    })
  end)

  _token_fetch_in_progress = false

  if not ok then
    log:error("Copilot Adapter: Could not authorize your GitHub Copilot token: %s", request)
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, request.body or "")
  if not ok or type(decoded) ~= "table" then
    log:error("Copilot Adapter: Could not decode token response: %s", request.body)
    return nil
  end

  M._copilot_token = decoded --[[@as CopilotToken]]
  return M._copilot_token
end

---Get and authorize a GitHub Copilot token
---@param adapter? CodeCompanion.HTTPAdapter
---@return boolean success
function M.init(adapter)
  M._oauth_token = get_oauth_token()
  if not M._oauth_token then
    log:error("Copilot Adapter: No token found. Please refer to https://github.com/github/copilot.vim")
    return false
  end

  M._copilot_token = get_copilot_token()
  if not M._copilot_token or vim.tbl_isempty(M._copilot_token) then
    log:error("Copilot Adapter: Could not authorize your GitHub Copilot token")
    return false
  end

  if adapter then
    adapter.url = M._copilot_token.endpoints and (M._copilot_token.endpoints.api .. "/chat/completions") or adapter.url
  end

  return true
end

---Return the Copilot tokens without initializing them
---@param opts? { force: boolean }
---@return { oauth_token: CopilotOAuthToken, copilot_token: CopilotToken|nil }
function M.fetch(opts)
  opts = opts or {}

  -- Only initialize tokens if explicitly requested or if we already have an oauth token cached
  if opts.force or M._oauth_token then
    pcall(M.init)
  end

  return {
    oauth_token = M._oauth_token,
    copilot_token = (M._copilot_token and M._copilot_token.token) or nil,
    endpoints = (M._copilot_token and M._copilot_token.endpoints) or nil,
  }
end

return M
