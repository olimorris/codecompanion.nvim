local Job = require("plenary.job")
local anthropic = require("codecompanion.adapters.anthropic")
local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")

local fmt = string.format

local _api_key

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

local CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
local REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback"
local AUTH_URL = "https://console.anthropic.com/oauth/authorize"
local TOKEN_URL = "https://api.anthropic.com/v1/oauth/token"
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

  local content = vim.fn.readfile(token_file)
  if not content or #content == 0 then
    return nil
  end

  local data = vim.json.decode(table.concat(content, "\n"))
  if data and data.api_key then
    _api_key = data.api_key
    return data.api_key
  end

  return nil
end

---Save API key to file
---@param api_key string
---@return boolean
local function save_api_key(api_key)
  local token_file = get_token_file_path()
  if not token_file then
    log:error("Anthropic OAuth: Could not determine token file path")
    return false
  end

  local data = {
    api_key = api_key,
    created_at = os.time(),
  }

  local success, err = pcall(function()
    vim.fn.writefile({ vim.json.encode(data) }, token_file)
  end)

  if success then
    _api_key = api_key
    return true
  else
    log:error("Anthropic OAuth: Failed to save API key: %s", err)
    return false
  end
end

---Create an API key using the OAuth access token
---@param access_token string
---@return string|nil
local function create_api_key(access_token)
  log:debug("Anthropic OAuth: Creating API key")

  local response = curl.post("https://api.anthropic.com/api/oauth/claude_cli/create_api_key", {
    headers = {
      ["Content-Type"] = "application/json",
      ["authorization"] = "Bearer " .. access_token,
    },
    body = vim.json.encode({}),
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    on_error = function(err)
      log:error("Anthropic OAuth: Create API key error %s", err)
    end,
  })

  if response.status >= 400 then
    log:error("Anthropic OAuth: Create API key failed with status %d: %s", response.status, response.body)
    return nil
  end

  local api_key_data = vim.json.decode(response.body)
  if not api_key_data or not api_key_data.raw_key then
    log:error("Anthropic OAuth: Invalid API key response")
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
    scope = SCOPES,
  }

  log:debug("Anthropic OAuth: Token exchange request data: %s", vim.inspect(request_data))

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

  log:debug("Anthropic OAuth: Token response data: %s", vim.inspect(token_data))

  -- Now use the access token to create an API key
  local api_key = create_api_key(token_data.access_token)
  if api_key then
    save_api_key(api_key)
    return api_key
  end

  return nil
end



local function generate_auth_url()
  local pkce = generate_pkce()

  -- Build query string manually to ensure proper encoding and order
  local query_params = {
    "code=true",
    "client_id=" .. url_encode(CLIENT_ID),
    "response_type=code",
    "redirect_uri=" .. url_encode(REDIRECT_URI),
    "scope=" .. url_encode(SCOPES),
    "code_challenge=" .. url_encode(pkce.challenge),
    "code_challenge_method=S256",
    "state=" .. url_encode(pkce.verifier),
  }

  local auth_url = AUTH_URL .. "?" .. table.concat(query_params, "&")

  log:debug("Anthropic OAuth: Generated auth URL: %s", auth_url)

  return {
    url = auth_url,
    verifier = pkce.verifier,
  }
end

local function get_api_key()
  -- Try to load from file
  local api_key = load_api_key()
  if api_key then
    return api_key
  end

  -- Need new OAuth flow
  log:error(
    "Anthropic OAuth: No API key found. Please run :AnthropicOAuthClear and then :AnthropicOAuthSetup to authenticate"
  )
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

    local api_key = exchange_code_for_api_key(code, auth_data.verifier)
    if api_key then
      _api_key = api_key
      vim.notify("Anthropic OAuth authentication successful! API key created.", vim.log.levels.INFO)
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
  local api_key = load_api_key()
  if not api_key then
    vim.notify("No Anthropic API key found. Run :AnthropicOAuthSetup to authenticate.", vim.log.levels.WARN)
    return
  end

  vim.notify("Anthropic API key is configured and ready to use.", vim.log.levels.INFO)
end, {
  desc = "Check Anthropic OAuth API key status",
})

-- Create user command to clear OAuth API key
vim.api.nvim_create_user_command("AnthropicOAuthClear", function()
  local token_file = get_token_file_path()
  if token_file and vim.fn.filereadable(token_file) == 1 then
    vim.fn.delete(token_file)
    _api_key = nil
    vim.notify("Anthropic API key cleared.", vim.log.levels.INFO)
  else
    vim.notify("No Anthropic API key found to clear.", vim.log.levels.WARN)
  end
end, {
  desc = "Clear stored Anthropic OAuth API key",
})

local adapter = vim.tbl_deep_extend("force", vim.deepcopy(anthropic), {
  name = "anthropic_oauth",
  formatted_name = "Anthropic (OAuth)",

  env = {
    ---@return string|nil
    api_key = function()
      return get_api_key()
    end,
  },
})

adapter.headers = {
  ["content-type"] = "application/json",
  ["x-api-key"] = "${api_key}",
  ["anthropic-version"] = "2023-06-01",
  ["anthropic-beta"] = "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14",
}

-- Override model schema with latest models
adapter.schema = vim.tbl_deep_extend("force", anthropic.schema or {}, {
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
        opts = { can_reason = true, has_vision = true, has_token_efficient_tools = true } 
      },
      ["claude-3-5-haiku-20241022"] = { opts = { has_vision = true } },
    },
  },
})

-- Add the filter_out_messages function
local function filter_out_messages(message)
  local allowed = {
    "content",
    "role",
    "reasoning",
    "tool_calls",
  }

  for key, _ in pairs(message) do
    if not vim.tbl_contains(allowed, key) then
      message[key] = nil
    end
  end
  return message
end

adapter.handlers = vim.tbl_extend("force", anthropic.handlers, {
  ---Check for a valid API key before starting the request
  ---@param self CodeCompanion.Adapter
  ---@return boolean
  setup = function(self)
    -- Get API key
    local api_key = get_api_key()
    if not api_key then
      vim.notify(
        "No Anthropic API key found. Run :AnthropicOAuthClear then :AnthropicOAuthSetup to authenticate.",
        vim.log.levels.ERROR
      )
      return false
    end

    -- Same as current setup function but removing additional headers
    if self.opts and self.opts.stream then
      self.parameters.stream = true
    end

    local model = self.schema.model.default
    local model_opts = self.schema.model.choices[model]
    if model_opts and model_opts.opts then
      self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
      if not model_opts.opts.has_vision then
        self.opts.vision = false
      end
    end

    return true
  end,

  ---Format messages with Claude Code system message at the beginning
  ---@param self CodeCompanion.Adapter
  ---@param messages table
  ---@return table
  form_messages = function(self, messages)
    local utils = require("codecompanion.utils.adapters")
    local tokens = require("codecompanion.utils.tokens")

    local has_tools = false

    local system = vim
      .iter(messages)
      :filter(function(msg)
        return msg.role == "system"
      end)
      :map(function(msg)
        return {
          type = "text",
          text = msg.content,
          cache_control = nil,
        }
      end)
      :totable()

    -- Add the Claude Code system message at the beginning (required for OAuth to work)
    table.insert(system, 1, {
      type = "text",
      text = "You are Claude Code, Anthropic's official CLI for Claude.",
      cache_control = {
        type = "ephemeral",
      },
    })

    system = next(system) and system or nil

    messages = vim
      .iter(messages)
      :filter(function(msg)
        return msg.role ~= "system"
      end)
      :totable()

    messages = vim.tbl_map(function(message)
      if message.opts and message.opts.tag == "image" and message.opts.mimetype then
        if self.opts and self.opts.vision then
          message.content = {
            {
              type = "image",
              source = {
                type = "base64",
                media_type = message.opts.mimetype,
                data = message.content,
              },
            },
          }
        else
          return nil
        end
      end

      message = filter_out_messages(message)

      if message.role == self.roles.user or message.role == self.roles.llm then
        if message.role == self.roles.user and message.content == "" then
          message.content = "<prompt></prompt>"
        end

        if type(message.content) == "string" then
          message.content = {
            { type = "text", text = message.content },
          }
        end
      end

      if message.tool_calls and vim.tbl_count(message.tool_calls) > 0 then
        has_tools = true
      end

      if message.role == "tool" then
        message.role = self.roles.user
      end

      if has_tools and message.role == self.roles.llm and message.tool_calls then
        if type(message.content) == "string" then
          message.content = {
            { type = "text", text = message.content },
          }
        elseif not message.content then
          message.content = {}
        end
        for _, call in ipairs(message.tool_calls) do
          table.insert(message.content, {
            type = "tool_use",
            id = call.id,
            name = call["function"].name,
            input = vim.json.decode(call["function"].arguments),
          })
        end
        message.tool_calls = nil
      end

      if message.reasoning and type(message.content) == "table" then
        table.insert(message.content, 1, {
          type = "thinking",
          thinking = message.reasoning.content,
          signature = message.reasoning._data.signature,
        })
      end

      return message
    end, messages)

    messages = utils.merge_messages(messages)

    if has_tools then
      for _, m in ipairs(messages) do
        if m.role == self.roles.user and m.content and m.content ~= "" then
          if type(m.content) == "table" and m.content.type then
            m.content = { m.content }
          end

          if type(m.content) == "table" and vim.islist(m.content) then
            local consolidated = {}
            for _, block in ipairs(m.content) do
              if block.type == "tool_result" then
                local prev = consolidated[#consolidated]
                if prev and prev.type == "tool_result" and prev.tool_use_id == block.tool_use_id then
                  prev.content = prev.content .. block.content
                else
                  table.insert(consolidated, block)
                end
              else
                table.insert(consolidated, block)
              end
            end
            m.content = consolidated
          end
        end
      end
    end

    local breakpoints_used = 0
    for i = #messages, 1, -1 do
      local msgs = messages[i]
      if msgs.role == self.roles.user then
        for _, msg in ipairs(msgs.content) do
          if msg.type ~= "text" or msg.text == "" then
            goto continue
          end
          if tokens.calculate(msg.text) >= self.opts.cache_over and breakpoints_used < self.opts.cache_breakpoints then
            msg.cache_control = { type = "ephemeral" }
            breakpoints_used = breakpoints_used + 1
          end
          ::continue::
        end
      end
    end
    if system and breakpoints_used < self.opts.cache_breakpoints then
      for _, prompt in ipairs(system) do
        if breakpoints_used < self.opts.cache_breakpoints then
          prompt.cache_control = { type = "ephemeral" }
          breakpoints_used = breakpoints_used + 1
        end
      end
    end

    return { system = system, messages = messages }
  end,
})

return adapter
