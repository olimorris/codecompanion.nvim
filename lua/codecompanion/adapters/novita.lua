local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

local _cache_expires
local _cache_file = vim.fn.tempname()
local _cached_models

---Get a list of available models
---@params self CodeCompanion.Adapter
---@params opts? table
---@return table
local function get_models(self, opts)
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    return _cached_models
  end

  local url = "https://api.novita.ai/v3/openai/models"

  local ok, response = pcall(function()
    return Curl.get(url, {
      sync = true,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get the Novita models from " .. url .. "\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing the response from " .. url .. "\nError: %s", response.body)
    return {}
  end

  local models = {}
  for _, model in ipairs(json.data) do
    if model.model_type == "chat" then
      table.insert(models, model.id)
    end
  end

  _cached_models = models
  _cache_expires = utils.refresh_cache(_cache_file, config.adapters.opts.cache_models_for)

  return models
end

---@class Novita.Adapter: CodeCompanion.Adapter
return {
  name = "novita",
  formatted_name = "Novita",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
    vision = false,
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "https://api.novita.ai/v3/openai/chat/completions",
  env = {
    api_key = "NOVITA_API_KEY",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
  },
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
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
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      ---@type string|fun(): string
      default = "meta-llama/llama-3.1-8b-instruct",
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
    top_k = {
      order = 4,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = -1,
      desc = "Integer that controls the number of top tokens to consider. Set to -1 to consider all tokens",
      validate = function(n)
        return n >= -1, "Must be greater than or equal to -1"
      end,
    },
    min_p = {
      order = 5,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Float that represents the minimum probability for a token to be considered, relative to the probability of the most likely token",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    stop = {
      order = 6,
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
    n = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "How many chat completion choices to generate for each input message. Note that you will be charged based on the number of generated tokens across all of the choices",
      validate = function(n)
        return n >= 1, "Must be greater than or equal to 1"
      end,
    },
    presence_penalty = {
      order = 8,
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
      order = 9,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Float that penalizes new tokens based on their frequency in the generated text so far. Values > 0 encourage the model to use new tokens, while values < 0 encourage the model to repeat tokens",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    logit_bias = {
      order = 10,
      mapping = "parameters",
      type = "map",
      optional = true,
      default = nil,
      desc = "Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID) to an associated bias value from -100 to 100. Use https://platform.openai.com/tokenizer to find token IDs.",
      subtype_key = {
        type = "integer",
      },
      subtype = {
        type = "integer",
        validate = function(n)
          return n >= -100 and n <= 100, "Must be between -100 and 100"
        end,
      },
    },
  },
}
