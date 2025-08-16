local Job = require("plenary.job")
local anthropic = require("codecompanion.adapters.anthropic")
local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")

local fmt = string.format

local _access_token

local CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
local REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback"
local AUTH_URL = "https://console.anthropic.com/oauth/authorize"
local TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
local SCOPES = "org:create_api_key user:profile user:inference"

local function generate_random_string(length)
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  local result = {}
  for i = 1, length do
    local rand_index = math.random(1, #chars)
    table.insert(result, chars:sub(rand_index, rand_index))
  end
  return table.concat(result)
end

local function sha256_base64url(input)
  -- Try to use proper SHA256 with OpenSSL
  if vim.fn.executable("openssl") == 1 then
    local job = Job:new({
      command = "openssl",
      args = { "dgst", "-sha256", "-binary" },
      writer = input,
      enable_recording = true,
    })

    local success, _ = pcall(function()
      job:sync(3000) -- 3 second timeout
    end)

    if success and job.code == 0 then
      local hash_binary = table.concat(job:result(), "")
      if hash_binary ~= "" then
        local base64 = vim.base64.encode(hash_binary)
        return base64:gsub("[+/=]", { ["+"] = "-", ["/"] = "_", ["="] = "" })
      end
    end
  end

  -- Fallback: not cryptographically secure but functional
  log:warn("Using fallback hash method (not cryptographically secure)")
  local simple_hash = vim.base64.encode(input)
  return simple_hash:gsub("[+/=]", { ["+"] = "-", ["/"] = "_", ["="] = "" })
end

local function generate_pkce()
  local verifier = generate_random_string(43) -- PKCE spec: 43-128 characters
  local challenge = sha256_base64url(verifier)
  return {
    verifier = verifier,
    challenge = challenge,
  }
end

---Finds the configuration path for storing OAuth tokens
---@return string|nil
local function find_config_path()
  if os.getenv("CODECOMPANION_ANTHROPIC_TOKEN_PATH") then
    return os.getenv("CODECOMPANION_ANTHROPIC_TOKEN_PATH")
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

---Get the OAuth token file path
---@return string|nil
local function get_token_file_path()
  local config_path = find_config_path()
  if not config_path then
    return nil
  end

  local anthropic_dir = config_path .. "/codecompanion/anthropic"

  -- Create directory if it doesn't exist
  if vim.fn.isdirectory(anthropic_dir) == 0 then
    vim.fn.mkdir(anthropic_dir, "p")
  end

  return anthropic_dir .. "/oauth_token.json"
end

---Load OAuth token from file
---@return AnthropicOAuthToken|nil
local function load_oauth_token()
  if _oauth_token_cache then
    return _oauth_token_cache
  end

  local token_file = get_token_file_path()
  if not token_file or vim.fn.filereadable(token_file) == 0 then
    return nil
  end

  local content = vim.fn.readfile(token_file)
  if not content or #content == 0 then
    return nil
  end

  local token_data = vim.json.decode(table.concat(content, "\n"))
  if token_data and token_data.expires_at and token_data.expires_at > os.time() then
    _oauth_token_cache = token_data
    return token_data
  end

  return nil
end

---Save OAuth token to file
---@param token AnthropicOAuthToken
---@return boolean
local function save_oauth_token(token)
  local token_file = get_token_file_path()
  if not token_file then
    log:error("Anthropic OAuth: Could not determine token file path")
    return false
  end

  local success, err = pcall(function()
    vim.fn.writefile({ vim.json.encode(token) }, token_file)
  end)

  if success then
    _oauth_token_cache = token
    return true
  else
    log:error("Anthropic OAuth: Failed to save token: %s", err)
    return false
  end
end

---Exchange authorization code for access token
---@param code string
---@param verifier string
---@return AnthropicOAuthToken|nil
local function exchange_code_for_token(code, verifier)
  log:debug("Anthropic OAuth: Exchanging authorization code for access token")

  -- Parse code and state from the callback URL fragment
  local code_parts = vim.split(code, "#")
  local auth_code = code_parts[1]
  local state = code_parts[2] or verifier

  local request_data = {
    code = auth_code,
    state = state,
    grant_type = "authorization_code",
    client_id = CLIENT_ID,
    redirect_uri = REDIRECT_URI,
    code_verifier = verifier,
  }

  local response = curl.post(TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = vim.json.encode(request_data),
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    on_error = function(err)
      log:error("Anthropic OAuth: Token exchange error %s", err)
    end,
  })

  if response.status >= 400 then
    log:error("Anthropic OAuth: Token exchange failed with status %d: %s", response.status, response.body)
    return nil
  end

  local token_data = vim.json.decode(response.body)
  if not token_data or not token_data.access_token then
    log:error("Anthropic OAuth: Invalid token response")
    return nil
  end

  local oauth_token = {
    access_token = token_data.access_token,
    refresh_token = token_data.refresh_token,
    expires_at = os.time() + (token_data.expires_in or 3600),
    token_type = token_data.token_type or "Bearer",
  }

  save_oauth_token(oauth_token)
  return oauth_token
end

---Refresh the access token using refresh token
---@param refresh_token string
---@return AnthropicOAuthToken|nil
local function refresh_access_token(refresh_token)
  log:debug("Anthropic OAuth: Refreshing access token")

  local request_data = {
    grant_type = "refresh_token",
    refresh_token = refresh_token,
    client_id = CLIENT_ID,
  }

  local response = curl.post(TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = vim.json.encode(request_data),
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    on_error = function(err)
      log:error("Anthropic OAuth: Token refresh error %s", err)
    end,
  })

  if response.status >= 400 then
    log:error("Anthropic OAuth: Token refresh failed with status %d: %s", response.status, response.body)
    return nil
  end

  local token_data = vim.json.decode(response.body)
  if not token_data or not token_data.access_token then
    log:error("Anthropic OAuth: Invalid refresh response")
    return nil
  end

  local oauth_token = {
    access_token = token_data.access_token,
    refresh_token = token_data.refresh_token or refresh_token,
    expires_at = os.time() + (token_data.expires_in or 3600),
    token_type = token_data.token_type or "Bearer",
  }

  save_oauth_token(oauth_token)
  return oauth_token
end

---Generate OAuth authorization URL
---@return table {url: string, verifier: string}
local function generate_auth_url()
  local pkce = generate_pkce()

  local params = {
    client_id = CLIENT_ID,
    response_type = "code",
    redirect_uri = REDIRECT_URI,
    scope = SCOPES,
    code_challenge = pkce.challenge,
    code_challenge_method = "S256",
    state = pkce.verifier,
  }

  local query_string = {}
  for key, value in pairs(params) do
    table.insert(query_string, key .. "=" .. vim.uri_encode(value))
  end

  local auth_url = AUTH_URL .. "?" .. table.concat(query_string, "&")

  return {
    url = auth_url,
    verifier = pkce.verifier,
  }
end

---Get valid access token (load from cache, refresh if needed, or prompt for OAuth)
---@return string|nil
local function get_access_token()
  if _access_token and _access_token.expires_at > os.time() + 60 then -- 60 second buffer
    return _access_token.access_token
  end

  -- Try to load from file
  local stored_token = load_oauth_token()
  if stored_token then
    if stored_token.expires_at > os.time() + 60 then
      _access_token = stored_token
      return stored_token.access_token
    elseif stored_token.refresh_token then
      -- Try to refresh
      local refreshed_token = refresh_access_token(stored_token.refresh_token)
      if refreshed_token then
        _access_token = refreshed_token
        return refreshed_token.access_token
      end
    end
  end

  -- Need new OAuth flow
  log:error("Anthropic OAuth: No valid token found. Please run :AnthropicOAuthSetup to authenticate")
  return nil
end

---Setup OAuth authentication (interactive)
---@return boolean
local function setup_oauth()
  local auth_data = generate_auth_url()

  vim.notify("Opening Anthropic OAuth authentication in your browser...", vim.log.levels.INFO)

  -- Open the URL in the default browser
  if vim.fn.has("mac") == 1 then
    vim.fn.system("open '" .. auth_data.url .. "'")
  elseif vim.fn.has("unix") == 1 then
    vim.fn.system("xdg-open '" .. auth_data.url .. "'")
  elseif vim.fn.has("win32") == 1 then
    vim.fn.system("start '" .. auth_data.url .. "'")
  else
    vim.notify("Please open this URL in your browser:\n" .. auth_data.url, vim.log.levels.INFO)
  end

  -- Prompt user for the authorization code
  vim.ui.input({
    prompt = "Enter the authorization code from the callback URL (the part after 'code='): ",
  }, function(code)
    if not code or code == "" then
      vim.notify("OAuth setup cancelled", vim.log.levels.WARN)
      return
    end

    local token = exchange_code_for_token(code, auth_data.verifier)
    if token then
      _access_token = token
      vim.notify("Anthropic OAuth authentication successful!", vim.log.levels.INFO)
    else
      vim.notify("Anthropic OAuth authentication failed", vim.log.levels.ERROR)
    end
  end)

  return true
end

vim.api.nvim_create_user_command("AnthropicOAuthSetup", function()
  setup_oauth()
end, {
  desc = "Setup Anthropic OAuth authentication",
})

-- Create user command to check OAuth status
vim.api.nvim_create_user_command("AnthropicOAuthStatus", function()
  local stored_token = load_oauth_token()
  if not stored_token then
    vim.notify("No Anthropic OAuth token found. Run :AnthropicOAuthSetup to authenticate.", vim.log.levels.WARN)
    return
  end

  local time_remaining = stored_token.expires_at - os.time()
  if time_remaining > 0 then
    local hours = math.floor(time_remaining / 3600)
    local minutes = math.floor((time_remaining % 3600) / 60)
    vim.notify(fmt("Anthropic OAuth token is valid. Expires in %dh %dm", hours, minutes), vim.log.levels.INFO)
  else
    vim.notify("Anthropic OAuth token has expired. Run :AnthropicOAuthSetup to re-authenticate.", vim.log.levels.WARN)
  end
end, {
  desc = "Check Anthropic OAuth token status",
})

-- Create user command to clear OAuth token
vim.api.nvim_create_user_command("AnthropicOAuthClear", function()
  local token_file = get_token_file_path()
  if token_file and vim.fn.filereadable(token_file) == 1 then
    vim.fn.delete(token_file)
    _oauth_token_cache = nil
    _access_token = nil
    vim.notify("Anthropic OAuth token cleared.", vim.log.levels.INFO)
  else
    vim.notify("No Anthropic OAuth token found to clear.", vim.log.levels.WARN)
  end
end, {
  desc = "Clear stored Anthropic OAuth token",
})

local adapter = vim.tbl_deep_extend("force", vim.deepcopy(anthropic), {
  name = "anthropic_oauth",
  formatted_name = "Anthropic (OAuth)",

  env = {
    ---@return string|nil
    api_key = function()
      return get_access_token()
    end,
  },
})

-- Override headers to use OAuth authentication
adapter.headers = {
  ["content-type"] = "application/json",
  ["authorization"] = "Bearer ${api_key}",
  ["anthropic-version"] = "2023-06-01",
  ["anthropic-beta"] = "prompt-caching-2024-07-31",
}
-- Remove the x-api-key header that comes from the base adapter
adapter.headers["x-api-key"] = nil

-- Override handlers
adapter.handlers = vim.tbl_extend("force", anthropic.handlers, {
  ---Check for a valid OAuth token before starting the request
  ---@param self CodeCompanion.Adapter
  ---@return boolean
  setup = function(self)
    -- Get access token (this will handle refresh if needed)
    local token = get_access_token()
    if not token then
      vim.notify("No valid Anthropic OAuth token. Run :AnthropicOAuthSetup to authenticate.", vim.log.levels.ERROR)
      return false
    end

    -- Call the original setup function from anthropic adapter
    return anthropic.handlers.setup(self)
  end,
})

return adapter
