local Curl = require("plenary.curl")
local adapter_utils = require("codecompanion.adapters.utils")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.http.openai")

local _cache_expires
local _cached_models

---Get a list of available models
---@params self CodeCompanion.HTTPAdapter
---@params opts? table
---@return table
local function get_models(self, opts)
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    return _cached_models
  end

  local url = "https://api.trustedrouter.com/v1/models"

  local ok, response = pcall(function()
    return Curl.get(url, {
      sync = true,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get the TrustedRouter models from " .. url .. "\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing the response from " .. url .. "\nError: %s", response.body)
    return {}
  end

  local models = {}
  for _, model in ipairs(json.data) do
    local modalities = model.architecture and model.architecture.input_modalities
    local choice_opts = {}

    if modalities and vim.tbl_contains(modalities, "image") then
      choice_opts.has_vision = true
    end

    models[model.id] = { opts = choice_opts }
  end

  _cached_models = models
  _cache_expires = adapter_utils.cache_expiry(config.adapters.http.opts.cache_models_for)

  return models
end

---@class CodeCompanion.HTTPAdapter.TrustedRouter: CodeCompanion.HTTPAdapter
return {
  name = "trustedrouter",
  formatted_name = "TrustedRouter",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
    tools = true,
    vision = true,
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "https://api.trustedrouter.com/v1/chat/completions",
  env = {
    api_key = "TRUSTEDROUTER_API_KEY",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
  },
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.HTTPAdapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      local choices = self.schema.model.choices
      if type(model) == "function" then
        model = model(self)
      end
      if type(choices) == "function" then
        choices = choices(self, { async = false })
      end
      local model_opts = choices[model]

      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end
      if (self.opts and self.opts.vision) and (model_opts and model_opts.opts and not model_opts.opts.has_vision) then
        self.opts.vision = false
      end
      return true
    end,

    --- Use the OpenAI adapter for the bulk of the work
    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
    end,
    form_messages = function(self, messages)
      return openai.handlers.form_messages(self, messages)
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
      return openai.handlers.on_exit(self, data)
    end,
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. Ids are namespaced (`anthropic/claude-opus-4-7`); a bare id is rejected. Ids under `trustedrouter/` are routing policies rather than single models - each picks an upstream per request and fails over, with `zdr` and `e2e` constraining routing to no-retention and confidential-compute providers.",
      ---@type string|fun(): string
      default = "trustedrouter/auto",
      ---@return table
      choices = function(self)
        return get_models(self)
      end,
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    stop = {
      order = 4,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Up to 4 sequences where the API will stop generating further tokens.",
      validate = function(l)
        return #l >= 1 and #l <= 4, "Must have between 1 and 4 elements"
      end,
    },
    presence_penalty = {
      order = 5,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Float that penalizes new tokens based on whether they appear in the generated text so far. Values > 0 encourage the model to use new tokens, while values < 0 encourage the model to repeat tokens",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    frequency_penalty = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Float that penalizes new tokens based on their frequency in the generated text so far. Values > 0 encourage the model to use new tokens, while values < 0 encourage the model to repeat tokens",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
  },
}
