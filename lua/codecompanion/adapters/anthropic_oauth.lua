local Job = require("plenary.job")
local anthropic = require("codecompanion.adapters.anthropic")
local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")

-- Module-level cache for the API key
local _api_key

---Constants for OAuth flow
local OAUTH_CONFIG = {
  CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback",
  AUTH_URL = "https://console.anthropic.com/oauth/authorize",
  TOKEN_URL = "https://api.anthropic.com/v1/oauth/token",
  API_KEY_URL = "https://api.anthropic.com/api/oauth/claude_cli/create_api_key",
  SCOPES = "org:create_api_key user:profile user:inference",
}

---Proper URL encoding function
---@param str string
---@return string
local function url_encode(str)
  if str then
    str = string.gsub(str, "\n", "\r\n")
    str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
  end
  return str
end

---Generate cryptographically secure random string for PKCE
---@param length number
---@return string
local function generate_random_string(length)
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  local result = {}
  
  -- Use Lua's improved random seed
  math.randomseed(os.time() * os.clock())
  
  for i = 1, length do
    local rand_index = math.random(1, #chars)
    table.insert(result, chars:sub(rand_index, rand_index))
  end
  return table.concat(result)
end

---Generate SHA256 hash in base64url format for PKCE challenge
---@param input string
---@return string
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
    else
      log:warn("OpenSSL command failed with code: %s", job.code)
    end
  else
    log:warn("OpenSSL not available, falling back to insecure hash method")
  end

  -- Fallback: not cryptographically secure but functional
  log:warn("Using fallback hash method (not cryptographically secure)")
  local simple_hash = vim.base64.encode(input)
  return simple_hash:gsub("[+/=]", { ["+"] = "-", ["/"] = "_", ["="] = "" })
end

---Generate PKCE code verifier and challenge
---@return { verifier: string, challenge: string }
local function generate_pkce()
  local verifier = generate_random_string(128) -- Use maximum length for better security
  local challenge = sha256_base64url(verifier)
  return {
    verifier = verifier,
    challenge = challenge,
  }
end

---Finds the configuration path for storing OAuth tokens
---@return string|nil
local function find_config_path()
  -- Check environment variable first
  local env_path = os.getenv("CODECOMPANION_ANTHROPIC_TOKEN_PATH")
  if env_path and vim.fn.isdirectory(vim.fs.dirname(env_path)) > 0 then
    return vim.fs.dirname(env_path)
  end

  -- Standard XDG config directory
  local xdg_config = os.getenv("XDG_CONFIG_HOME")
  if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
    return xdg_config
  end

  -- Platform-specific fallbacks
  if vim.fn.has("win32") > 0 then
    local app_data = vim.fs.normalize("~/AppData/Local")
    if vim.fn.isdirectory(app_data) > 0 then
      return app_data
    end
  else
    local config_home = vim.fs.normalize("~/.config")
    if vim.fn.isdirectory(config_home) > 0 then
      return config_home
    end
  end

  return nil
end

---Get the OAuth token file path
---@return string|nil
local function get_token_file_path()
  local config_path = find_config_path()
  if not config_path then
    log:error("Anthropic OAuth: Could not determine config directory")
    return nil
  end

  local anthropic_dir = config_path .. "/codecompanion/anthropic"

  -- Create directory if it doesn't exist
  if vim.fn.isdirectory(anthropic_dir) == 0 then
    local success = vim.fn.mkdir(anthropic_dir, "p")
    if success == 0 then
      log:error("Anthropic OAuth: Failed to create directory: %s", anthropic_dir)
      return nil
    end
  end

  return anthropic_dir .. "/oauth_token.json"
end

---Load API key from file
---@return string|nil
local function load_api_key()
  if _api_key then
    return _api_key
  end

  local token_file = get_token_file_path()
  if not token_file or vim.fn.filereadable(token_file) == 0 then
    return nil
  end

  local success, content = pcall(vim.fn.readfile, token_file)
  if not success or not content or #content == 0 then
    log:debug("Anthropic OAuth: Could not read token file or file is empty")
    return nil
  end

  local decode_success, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if decode_success and data and data.api_key then
    _api_key = data.api_key
    return data.api_key
  else
    log:warn("Anthropic OAuth: Invalid token file format")
    return nil
  end
end

---Save API key to file
---@param api_key string
---@return boolean
local function save_api_key(api_key)
  if not api_key or api_key == "" then
    log:error("Anthropic OAuth: Cannot save empty API key")
    return false
  end

  local token_file = get_token_file_path()
  if not token_file then
    return false
  end

  local data = {
    api_key = api_key,
    created_at = os.time(),
    version = 1, -- For future migrations if needed
  }

  local success, err = pcall(function()
    vim.fn.writefile({ vim.json.encode(data) }, token_file)
  end)

  if success then
    _api_key = api_key
    log:info("Anthropic OAuth: API key saved successfully")
    return true
  else
    log:error("Anthropic OAuth: Failed to save API key: %s", err or "unknown error")
    return false
  end
end

---Create an API key using the OAuth access token
---@param access_token string
---@return string|nil
local function create_api_key(access_token)
  if not access_token or access_token == "" then
    log:error("Anthropic OAuth: Access token is required")
    return nil
  end

  log:debug("Anthropic OAuth: Creating API key")

  local response = curl.post(OAUTH_CONFIG.API_KEY_URL, {
    headers = {
      ["Content-Type"] = "application/json",
      ["authorization"] = "Bearer " .. access_token,
    },
    body = vim.json.encode({}),
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    timeout = 30000, -- 30 second timeout
    on_error = function(err)
      log:error("Anthropic OAuth: Create API key request error: %s", vim.inspect(err))
    end,
  })

  if not response then
    log:error("Anthropic OAuth: No response from API key creation request")
    return nil
  end

  if response.status >= 400 then
    log:error("Anthropic OAuth: Create API key failed with status %d: %s", response.status, response.body or "no body")
    return nil
  end

  local decode_success, api_key_data = pcall(vim.json.decode, response.body)
  if not decode_success or not api_key_data or not api_key_data.raw_key then
    log:error("Anthropic OAuth: Invalid API key response format")
    return nil
  end

  log:debug("Anthropic OAuth: API key created successfully")
  return api_key_data.raw_key
end

---Exchange authorization code for access token and create API key
---@param code string
---@param verifier string
---@return string|nil
local function exchange_code_for_api_key(code, verifier)
  if not code or code == "" or not verifier or verifier == "" then
    log:error("Anthropic OAuth: Code and verifier are required")
    return nil
  end

  log:debug("Anthropic OAuth: Exchanging authorization code for access token")

  -- Parse code and state from the callback URL fragment
  local code_parts = vim.split(code, "#")
  local auth_code = code_parts[1]
  local state = code_parts[2] or verifier

  local request_data = {
    code = auth_code,
    state = state,
    grant_type = "authorization_code",
    client_id = OAUTH_CONFIG.CLIENT_ID,
    redirect_uri = OAUTH_CONFIG.REDIRECT_URI,
    code_verifier = verifier,
    scope = OAUTH_CONFIG.SCOPES,
  }

  log:debug("Anthropic OAuth: Token exchange request initiated")

  local response = curl.post(OAUTH_CONFIG.TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = vim.json.encode(request_data),
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    timeout = 30000, -- 30 second timeout
    on_error = function(err)
      log:error("Anthropic OAuth: Token exchange request error: %s", vim.inspect(err))
    end,
  })

  if not response then
    log:error("Anthropic OAuth: No response from token exchange request")
    return nil
  end

  if response.status >= 400 then
    log:error("Anthropic OAuth: Token exchange failed with status %d: %s", response.status, response.body or "no body")
    return nil
  end

  local decode_success, token_data = pcall(vim.json.decode, response.body)
  if not decode_success or not token_data or not token_data.access_token then
    log:error("Anthropic OAuth: Invalid token response format")
    return nil
  end

  log:debug("Anthropic OAuth: Access token obtained successfully")

  -- Now use the access token to create an API key
  local api_key = create_api_key(token_data.access_token)
  if api_key and save_api_key(api_key) then
    return api_key
  end

  return nil
end

---Generate OAuth authorization URL with PKCE
---@return { url: string, verifier: string }
local function generate_auth_url()
  local pkce = generate_pkce()

  -- Build query string with proper encoding and order
  local query_params = {
    "code=true",
    "client_id=" .. url_encode(OAUTH_CONFIG.CLIENT_ID),
    "response_type=code",
    "redirect_uri=" .. url_encode(OAUTH_CONFIG.REDIRECT_URI),
    "scope=" .. url_encode(OAUTH_CONFIG.SCOPES),
    "code_challenge=" .. url_encode(pkce.challenge),
    "code_challenge_method=S256",
    "state=" .. url_encode(pkce.verifier),
  }

  local auth_url = OAUTH_CONFIG.AUTH_URL .. "?" .. table.concat(query_params, "&")
  log:debug("Anthropic OAuth: Generated auth URL")

  return {
    url = auth_url,
    verifier = pkce.verifier,
  }
end

---Get API key, either from cache or file
---@return string|nil
local function get_api_key()
  -- Try to load from cache or file
  local api_key = load_api_key()
  if api_key then
    return api_key
  end

  -- Need new OAuth flow
  log:error("Anthropic OAuth: No API key found. Please run :AnthropicOAuthSetup to authenticate")
  return nil
end

---Setup OAuth authentication (interactive)
---@return boolean
local function setup_oauth()
  local auth_data = generate_auth_url()

  vim.notify("Opening Anthropic OAuth authentication in your browser...", vim.log.levels.INFO)

  -- Open the URL in the default browser
  local open_cmd
  if vim.fn.has("mac") == 1 then
    open_cmd = "open"
  elseif vim.fn.has("unix") == 1 then
    open_cmd = "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    open_cmd = "start"
  end

  if open_cmd then
    local success = pcall(vim.fn.system, open_cmd .. " '" .. auth_data.url .. "'")
    if not success then
      vim.notify("Could not open browser automatically. Please open this URL manually:\n" .. auth_data.url, vim.log.levels.WARN)
    end
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

    -- Show progress
    vim.notify("Exchanging authorization code for API key...", vim.log.levels.INFO)

    local api_key = exchange_code_for_api_key(code, auth_data.verifier)
    if api_key then
      _api_key = api_key
      vim.notify("Anthropic OAuth authentication successful! API key created and saved.", vim.log.levels.INFO)
    else
      vim.notify("Anthropic OAuth authentication failed. Please check the logs and try again.", vim.log.levels.ERROR)
    end
  end)

  return true
end

-- Create user commands for OAuth management
vim.api.nvim_create_user_command("AnthropicOAuthSetup", function()
  setup_oauth()
end, {
  desc = "Setup Anthropic OAuth authentication",
})

vim.api.nvim_create_user_command("AnthropicOAuthStatus", function()
  local api_key = load_api_key()
  if not api_key then
    vim.notify("No Anthropic API key found. Run :AnthropicOAuthSetup to authenticate.", vim.log.levels.WARN)
    return
  end

  vim.notify("Anthropic API key is configured and ready to use.", vim.log.levels.INFO)
end, {
  desc = "Check Anthropic OAuth API key status",
})

vim.api.nvim_create_user_command("AnthropicOAuthClear", function()
  local token_file = get_token_file_path()
  if token_file and vim.fn.filereadable(token_file) == 1 then
    local success = pcall(vim.fn.delete, token_file)
    if success then
      _api_key = nil
      vim.notify("Anthropic API key cleared.", vim.log.levels.INFO)
    else
      vim.notify("Failed to clear API key file.", vim.log.levels.ERROR)
    end
  else
    vim.notify("No Anthropic API key found to clear.", vim.log.levels.WARN)
  end
end, {
  desc = "Clear stored Anthropic OAuth API key",
})

-- Create the adapter by extending the base anthropic adapter
local adapter = vim.tbl_deep_extend("force", vim.deepcopy(anthropic), {
  name = "anthropic_oauth",
  formatted_name = "Anthropic (OAuth)",

  env = {
    ---Get the API key from OAuth flow
    ---@return string|nil
    api_key = function()
      return get_api_key()
    end,
  },

  headers = {
    ["content-type"] = "application/json",
    ["x-api-key"] = "${api_key}",
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14",
  },

  -- Override model schema with latest models
  schema = vim.tbl_deep_extend("force", anthropic.schema or {}, {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "The model that will complete your prompt. See https://docs.anthropic.com/claude/docs/models-overview for additional details and options.",
      default = "claude-sonnet-4-20250514",
      choices = {
        ["claude-opus-4-1-20250805"] = { opts = { can_reason = true, has_vision = true } },
        ["claude-opus-4-20250514"] = { opts = { can_reason = true, has_vision = true } },
        ["claude-sonnet-4-20250514"] = { opts = { can_reason = true, has_vision = true } },
        ["claude-3-7-sonnet-20250219"] = {
          opts = { can_reason = true, has_vision = true, has_token_efficient_tools = true },
        },
        ["claude-3-5-haiku-20241022"] = { opts = { has_vision = true } },
      },
    },
  }),
})

-- Override handlers to add OAuth-specific functionality and Claude Code system message
adapter.handlers = vim.tbl_extend("force", anthropic.handlers, {
  ---Check for a valid API key before starting the request
  ---@param self CodeCompanion.Adapter
  ---@return boolean
  setup = function(self)
    -- Get API key and validate
    local api_key = get_api_key()
    if not api_key then
      vim.notify(
        "No Anthropic API key found. Run :AnthropicOAuthSetup to authenticate.",
        vim.log.levels.ERROR
      )
      return false
    end

    -- Call the original setup function to handle streaming and model options
    return anthropic.handlers.setup(self)
  end,

  ---Format messages with Claude Code system message at the beginning (required for OAuth)
  ---@param self CodeCompanion.Adapter
  ---@param messages table
  ---@return table
  form_messages = function(self, messages)
    -- First, call the original form_messages to get the standard formatting
    local formatted = anthropic.handlers.form_messages(self, messages)
    
    -- Extract existing system messages or initialize empty array
    local system = formatted.system or {}
    
    -- Add the Claude Code system message at the beginning (required for OAuth to work)
    table.insert(system, 1, {
      type = "text",
      text = "You are Claude Code, Anthropic's official CLI for Claude.",
    })
    
    -- Return the formatted messages with our modified system messages
    return {
      system = system,
      messages = formatted.messages,
    }
  end,
})

return adapter