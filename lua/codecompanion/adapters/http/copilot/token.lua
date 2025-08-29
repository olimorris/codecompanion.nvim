local Curl = require("plenary.curl")

local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local M = {}

-- Reference: https://github.com/yetone/avante.nvim/blob/22418bff8bcac4377ebf975cd48f716823867979/lua/avante/providers/copilot.lua#L5-L26
---@class CopilotToken
---@field annotations_enabled boolean
---@field chat_enabled boolean
---@field chat_jetbrains_enabled boolean
---@field code_quote_enabled boolean
---@field codesearch boolean
---@field copilotignore_enabled boolean
---@field endpoints { api: string, ["origin-tracker"]: string, proxy: string, telemetry: string }
---@field expires_at number
---@field individual boolean
---@field nes_enabled boolean
---@field prompt_8k boolean
---@field public_suggestions string
---@field refresh_in number
---@field sku string
---@field snippy_load_test_enabled boolean
---@field telemetry string
---@field token string -- The actual token we use in our requests
---@field tracking_id string
---@field vsc_electron_fetcher boolean
---@field xcode boolean
---@field xcode_chat boolean

---@alias CopilotOAuthToken string|nil
M._oauth_token = nil

---@type CopilotToken|nil
M._copilot_token = nil

---Finds the configuration path
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

---The function first attempts to load the token from the environment variables,
---specifically for GitHub Codespaces. If not found, it then attempts to load
---the token from configuration files located in the user's configuration path.
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

  local file_paths = {
    config_path .. "/github-copilot/hosts.json",
    config_path .. "/github-copilot/apps.json",
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

  return nil
end

---Get a GitHub Copilot token using the OAuth token
---@return CopilotToken|nil
local function get_copilot_token()
  if M._copilot_token and M._copilot_token.expires_at > os.time() then
    log:trace("Reusing GitHub Copilot token")
    return M._copilot_token
  end

  log:debug("Authorizing GitHub Copilot token")

  local ok, request = pcall(function()
    return Curl.get("https://api.github.com/copilot_internal/v2/token", {
      headers = {
        Authorization = "Bearer " .. M._oauth_token,
        Accept = "application/json",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      on_error = function(err)
        log:error("Copilot Adapter: Token request error %s", err)
      end,
    })
  end)

  if not ok then
    log:error("Copilot Adapter: Could not authorize your GitHub Copilot token: %s", request)
    return nil
  end

  M._copilot_token = vim.json.decode(request.body)
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
    adapter.url = M._copilot_token.endpoints.api .. "/chat/completions"
  end

  return true
end

---Return the Copilot tokens
---@return {oauth_token: CopilotOAuthToken, copilot_token: CopilotToken|nil}
function M.fetch()
  M.init()

  return {
    oauth_token = M._oauth_token,
    copilot_token = M._copilot_token.token,
  }
end

return M
