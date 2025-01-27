local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

---@alias CopilotOAuthToken string|nil
local _oauth_token

---@alias CopilotToken {token: string, expires_at: number}|nil
local _github_token

--- Finds the configuration path
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
local function get_token()
  if _oauth_token then
    return _oauth_token
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
      local userdata = vim.json.decode(vim.fn.readfile(file_path)[1])
      for key, value in pairs(userdata) do
        if string.find(key, "github.com") then
          return value.oauth_token
        end
      end
    end
  end

  return nil
end

---Authorize the GitHub OAuth token
---@return CopilotToken
local function authorize_token()
  if _github_token and _github_token.expires_at > os.time() then
    log:debug("Reusing GitHub Copilot token")
    return _github_token
  end

  log:debug("Authorizing GitHub Copilot token")

  local request = curl.get("https://api.github.com/copilot_internal/v2/token", {
    headers = {
      Authorization = "Bearer " .. _oauth_token,
      ["Accept"] = "application/json",
    },
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    on_error = function(err)
      log:error("Copilot Adapter: Token request error %s", err)
    end,
  })

  _github_token = vim.json.decode(request.body)
  return _github_token
end

---@class Copilot.Adapter: CodeCompanion.Adapter
return {
  name = "copilot",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
  },
  features = {
    text = true,
    tokens = true,
    vision = false,
  },
  url = "https://api.githubcopilot.com/chat/completions",
  env = {
    ---@return string|nil
    api_key = function()
      return authorize_token().token
    end,
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
    ["Copilot-Integration-Id"] = "vscode-chat",
    ["editor-version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
  },
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
      end

      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end

      _oauth_token = get_token()
      if not _oauth_token then
        log:error("Copilot Adapter: No token found. Please refer to https://github.com/github/copilot.vim")
        return false
      end

      _github_token = authorize_token()
      if not _github_token or vim.tbl_isempty(_github_token) then
        log:error("Copilot Adapter: Could not authorize your GitHub Copilot token")
        return false
      end

      return true
    end,

    --- Use the OpenAI adapter for the bulk of the work
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      return openai.handlers.form_messages(self, messages)
    end,
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if json.usage then
            local total_tokens = json.usage.total_tokens or 0
            local completion_tokens = json.usage.completion_tokens or 0
            local prompt_tokens = json.usage.prompt_tokens or 0
            local tokens = total_tokens > 0 and total_tokens or completion_tokens + prompt_tokens
            log:trace("Tokens: %s", tokens)
            return tokens
          end
        end
      end
    end,
    chat_output = function(self, data)
      return openai.handlers.chat_output(self, data)
    end,
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    on_exit = function(self, data)
      return openai.handlers.on_exit(self, data)
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      ---@type string|fun(): string
      default = "gpt-4o-2024-08-06",
      choices = {
        "gpt-4o-2024-08-06",
        "claude-3.5-sonnet",
        "o1-2024-12-17",
        "o1-mini-2024-09-12",
      },
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      default = 0,
      condition = function(schema)
        local model = schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
    },
    max_tokens = {
      order = 3,
      mapping = "parameters",
      type = "integer",
      default = 4096,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
    },
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "number",
      default = 1,
      condition = function(schema)
        local model = schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
    },
    n = {
      order = 5,
      mapping = "parameters",
      type = "number",
      default = 1,
      condition = function(schema)
        local model = schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "How many chat completions to generate for each prompt.",
    },
  },
}
