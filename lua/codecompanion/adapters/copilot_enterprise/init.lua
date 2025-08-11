local config = require("codecompanion.config")
local openai = require("codecompanion.adapters.openai")
local copilot = require("codecompanion.adapters.copilot")
local helpers = require("codecompanion.adapters.copilot_enterprise.helpers")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")

---@alias CopilotEnterpriseOAuthToken string|nil
local _oauth_token
---@type CopilotToken|nil
local _github_token

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

---Load token from multiple sources.
---
---The function first tries to loads the token from environment variables,
---specifically for GitHub Codespaces, and a custom `GHE_COPILOT_TOKEN` variable.
---If not found, it attempts to load the token from configuration files located
---in the user's configuration path.
---@return CopilotEnterpriseOAuthToken|nil
local function get_token(self)
  if _oauth_token then
    return _oauth_token
  end

  local token = os.getenv("GITHUB_TOKEN")
  local codespaces = os.getenv("CODESPACES")
  if token and codespaces then
    return token
  end
  
  token = os.getenv("GHE_COPILOT_TOKEN")
  if token then
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

  local provider_url = self.opts.provider_url:gsub("^https?://", "")
  for _, file_path in ipairs(file_paths) do
    if vim.uv.fs_stat(file_path) then
      local userdata = vim.fn.readfile(file_path)

      if vim.islist(userdata) then
        userdata = table.concat(userdata, " ")
      end

      local userdata = vim.json.decode(userdata)
      for key, value in pairs(userdata) do
        if key:find(provider_url, 1, true) == 1 then
          return value.oauth_token
        end
      end
    end
  end

  return nil
end

---Authorize the GitHub OAuth token for Enterprise
---@return CopilotToken
local function authorize_token(self)
  if _github_token and _github_token.expires_at > os.time() then
    log:trace("Reusing Copilot Enterprise token")
    return _github_token
  end

  log:debug("Authorizing Copilot Enterprise token")

  local provider_url = self.opts.provider_url:gsub("^https?://", "")
  local api_url = "https://api." .. provider_url .. "/copilot_internal/v2/token"
  local request = curl.get(api_url, {
    headers = {
      Authorization = "Bearer " .. _oauth_token,
      ["Accept"] = "application/json",
    },
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    on_error = function(err)
      log:error("Copilot Enterprise Adapter: Token request error %s", err)
    end,
  })

  _github_token = vim.json.decode(request.body)
  return _github_token
end

---Get and authorize a GitHub Copilot Enterprise token
---@param self CodeCompanion.Adapter
---@return boolean success
---@return table|nil GitHub token on success
local function get_and_authorize_token(self)
  _oauth_token = get_token(self)
  if not _oauth_token then
    log:error("Copilot Enterprise Adapter: No token found. Please ensure you've configured your Copilot Enterprise token")
    return false
  end

  _github_token = authorize_token(self)
  if not _github_token or vim.tbl_isempty(_github_token) then
    log:error("Copilot Enterprise Adapter: Could not authorize your Copilot Enterprise token")
    return false
  end
  
  self.url = _github_token.endpoints.api .. "/chat/completions"
  return true, _github_token
end

---@class CopilotEnterprise.Adapter: CodeCompanion.Adapter
return {
  name = "copilot_enterprise",
  formatted_name = "Copilot Enterprise",
  roles = copilot.roles,
  opts = copilot.opts,
  features = copilot.features,
  url = copilot.url,
  env = {
    ---@return string|nil
    api_key = function()
      -- Token retrieved in `setup` function
      return _github_token and _github_token.token or nil
    end,
  },
  headers = copilot.headers,

  get_stats = function(self)
    return helpers.get_copilot_stats(self, get_and_authorize_token)
  end,

  show_stats = function(self)
    return helpers.show_copilot_stats(self, get_and_authorize_token)
  end,

  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      local choices = self.schema.model.choices
      if type(choices) == "function" then
        choices = choices(self)
      end
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model(self)
      end
      local model_opts = choices[model]

      self.parameters.stream =
        self.opts and self.opts.stream and model_opts and model_opts.opts and model_opts.opts.can_stream
      self.opts.tools =
        self.opts and self.opts.tools and model_opts and model_opts.opts and model_opts.opts.can_use_tools
      self.opts.vision =
        self.opts and self.opts.vision and model_opts and model_opts.opts and model_opts.opts.has_vision

      return get_and_authorize_token(self)
    end,

    form_parameters = copilot.handlers.form_parameters,
    form_messages = copilot.handlers.form_messages,
    form_tools = copilot.handlers.form_tools,
    tokens = copilot.handlers.tokens,
    chat_output = copilot.handlers.chat_output,
    tools = copilot.handlers.tools,
    inline_output = copilot.handlers.inline_output,

    on_exit = function(self, data)
      helpers.reset_cache()
      return openai.handlers.on_exit(self, data)
    end,
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model in use. Model availability may depend on you GitHub Enterprise plan.",
      ---@type string|fun(): string
      default = "gpt-4.1",
      choices = function(self)
        -- Ensure token is available before getting models
        if not _github_token then
          local success = get_and_authorize_token(self)
          if not success then
            return { ["gpt-4.1"] = { opts = {} } } -- fallback
          end
        end
        return helpers.get_models(self, get_and_authorize_token)
      end,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      default = 0.1,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model(self)
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic.",
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      default = 16384,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 5,
      mapping = "parameters",
      type = "number",
      default = 1,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model(self)
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass.",
    },
    ---@type CodeCompanion.Schema
    n = {
      order = 6,
      mapping = "parameters",
      type = "number",
      default = 1,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model(self)
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "How many chat completions to generate for each prompt.",
    },
  },
}
