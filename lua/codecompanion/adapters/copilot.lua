local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

local _cache_expires
local _cache_file = vim.fn.tempname()
local _cached_adapter
local _cached_models

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
      local userdata = vim.fn.readfile(file_path)

      if vim.islist(userdata) then
        userdata = table.concat(userdata, " ")
      end

      local userdata = vim.json.decode(userdata)
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
    log:trace("Reusing GitHub Copilot token")
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

---Get and authorize a GitHub Copilot token
---@return boolean success
local function get_and_authorize_token()
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
end

---Reset the cached adapter
---@return nil
local function reset()
  _cached_adapter = nil
end

---Get a list of available Copilot models
---@params self CodeCompanion.Adapter
---@params opts? table
---@return table
local function get_models(self, opts)
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    return _cached_models
  end

  if not _cached_adapter then
    if not self then
      return {}
    end
    _cached_adapter = self
  end

  get_and_authorize_token()
  local url = "https://api.githubcopilot.com"
  local headers = vim.deepcopy(_cached_adapter.headers)
  headers["Authorization"] = "Bearer " .. _github_token.token

  local ok, response = pcall(function()
    return curl.get(url .. "/models", {
      sync = true,
      headers = headers,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get the Copilot models from " .. url .. "/models.\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing the response from " .. url .. "/models.\nError: %s", response.body)
    return {}
  end

  local models = {}
  for _, model in ipairs(json.data) do
    if model.model_picker_enabled and model.capabilities.type == "chat" then
      local choice_opts = {}

      -- streaming support
      if model.capabilities.supports.streaming then
        choice_opts.can_stream = true
      end
      if model.capabilities.supports.tool_calls then
        choice_opts.can_use_tools = true
      end

      models[model.id] = { opts = choice_opts }
    end
  end

  _cached_models = models
  _cache_expires = utils.refresh_cache(_cache_file, config.adapters.opts.cache_models_for)

  return models
end

---@class Copilot.Adapter: CodeCompanion.Adapter
return {
  name = "copilot",
  formatted_name = "Copilot",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
    tools = true,
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
    ["Editor-Version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
  },
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      local choices = self.schema.model.choices
      if type(model) == "function" then
        model = model(self)
      end
      if type(choices) == "function" then
        choices = choices(self)
      end
      local model_opts = choices[model]

      if (self.opts and self.opts.stream) and (model_opts and model_opts.opts and model_opts.opts.can_stream) then
        self.parameters.stream = true
      else
        self.parameters.stream = nil
      end
      if (self.opts and self.opts.tools) and (model_opts and model_opts.opts and not model_opts.opts.can_use_tools) then
        self.opts.tools = false
      end

      return get_and_authorize_token()
    end,

    --- Use the OpenAI adapter for the bulk of the work
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      -- Extract any images from the messages table
      local images = {}
      vim.iter(messages):each(function(m)
        if m.opts and m.opts.tag == "image" and m.opts.base64 then
          images[m.content] = {
            base64 = m.opts.base64,
            mimetype = m.opts.mimetype,
          }
        end
      end)

      messages = openai.handlers.form_messages(self, messages).messages

      if vim.tbl_count(images) > 0 then
        self.headers["Copilot-Vision-Request"] = "true"

        -- Now replace the images to conform to the Copilot API
        messages = vim
          .iter(messages)
          :map(function(m)
            local image = images[m.content]
            if image then
              m.content = {
                {
                  type = "image_url",
                  image_url = {
                    url = string.format("data:%s;base64,%s", image.mimetype, image.base64),
                  },
                },
              }
            end
            return m
          end)
          :totable()
      end

      return { messages = messages }
    end,
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
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
    chat_output = function(self, data, tools)
      return openai.handlers.chat_output(self, data, tools)
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return openai.handlers.tools.output_response(self, tool_call, output)
      end,
    },
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    on_exit = function(self, data)
      reset()
      return openai.handlers.on_exit(self, data)
    end,
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      ---@type string|fun(): string
      default = "gpt-4o",
      choices = function(self)
        return get_models(self)
      end,
    },
    ---@type CodeCompanion.Schema
    reasoning_effort = {
      order = 2,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = "medium",
      desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.",
      choices = {
        "high",
        "medium",
        "low",
      },
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      default = 0,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
    },
    max_tokens = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      default = 15000,
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
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
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
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "How many chat completions to generate for each prompt.",
    },
  },
}
