local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")

---Cached list of available models
---@type table<string>
local _models = {}

---Get a list of available Venice models
---@params self CodeCompanion.Adapter
---@params opts? table
---@return table
local function get_models(self, opts)
  local adapter = require("codecompanion.adapters").resolve(self)
  if not adapter then
    log:error("Could not resolve Venice adapter in the `get_models` function")
    return {}
  end

  if vim.tbl_isempty(_models) or config.display.chat.show_settings == false then
    adapter:get_env_vars()
    local url = adapter.env_replaced.url

    local headers = {
      ["content-type"] = "application/json",
    }
    if adapter.env_replaced.api_key then
      headers["Authorization"] = "Bearer " .. adapter.env_replaced.api_key
    end

    local ok, response, json

    ok, response = pcall(function()
      return curl.get(url .. "/v1/models", {
        sync = true,
        headers = headers,
        insecure = config.adapters.opts.allow_insecure,
        proxy = config.adapters.opts.proxy,
      })
    end)
    if not ok then
      log:error("Could not get the Venice compatible models from " .. url .. "/v1/models.\nError: %s", response)
      return {}
    end

    ok, json = pcall(vim.json.decode, response.body)
    if not ok then
      log:error("Could not parse the response from " .. url .. "/v1/models")
      return {}
    end

    for _, model in ipairs(json.data) do
      table.insert(_models, model.id)
    end
  end

  if opts and opts.last then
    return _models[1]
  end
  return _models
end

---@class Venice.Adapter: CodeCompanion.Adapter
return {
  name = "venice",
  formatted_name = "Venice",
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
  url = "${url}${chat_url}",
  env = {
    api_key = "VENICE_API_KEY",
    url = "https://api.venice.ai/api",
    chat_url = "/v1/chat/completions",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  handlers = {
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
        self.parameters.stream_options = { include_usage = true }
      end
      return true
    end,

    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      return openai.handlers.form_messages(self, messages)
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
      desc =
      "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = function(self)
        return get_models(self, { last = true })
      end,
      choices = function(self)
        return get_models(self)
      end,
    },
    temperature = {
      order = 2,
      mapping = "parameterss",
      type = "number",
      optional = true,
      default = 0.8,
      desc =
      "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    stop = {
      order = 10,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = nil,
      desc =
      "Sets the stop sequences to use. When this pattern is encountered the LLM will stop generating text and return. Multiple stop patterns may be set by specifying multiple separate stop parameters in a modelfile.",
      validate = function(s)
        return s:len() > 0, "Cannot be an empty string"
      end,
    },
    top_p = {
      order = 14,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.9,
      desc =
      "Works together with top-k. A higher value (e.g., 0.95) will lead to more diverse text, while a lower value (e.g., 0.5) will generate more focused and conservative text. (Default: 0.9)",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    max_tokens = {
      order = 5,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc =
      "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    presence_penalty = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc =
      "Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    frequency_penalty = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc =
      "Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
  },
}
