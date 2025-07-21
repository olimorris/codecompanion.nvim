local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

-- Cache variables for models
local _cached_models
local _cache_expires
local _cache_file = vim.fn.tempname()

---Get a list of available Hugging Face models from inference providers
---@param adapter CodeCompanion.Adapter
---@return table
local function get_models(adapter)
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    return _cached_models
  end
  if not adapter.env.api_key then
    log:error("No Hugging Face API key found")
    return {}
  end
  local url = "https://huggingface.co/api/models?inference_provider=all"
  local headers = {
    ["User-Agent"] = "CodeCompanion.nvim",
  }
  local ok, response = pcall(function()
    return curl.get(url, {
      sync = true,
      headers = headers,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get Hugging Face models from %s.\nError: %s", url, response)
    return {}
  end
  local ok, models_data = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing Hugging Face models response: %s", response.body)
    return {}
  end
  local models = {}
  for _, model_data in ipairs(models_data) do
    if model_data.id then
      models[model_data.id] = { opts = { can_stream = true } }
    end
  end
  if vim.tbl_count(models) == 0 then
    log:warn("No models found from API, using fallback models")
    models = {
      ["meta-llama/Llama-3.1-8B-Instruct"] = { opts = { can_stream = true } },
      ["Qwen/Qwen2.5-32B-Instruct"] = { opts = { can_stream = true } },
      ["google/gemma-3-27b-it"] = { opts = { can_stream = true } },
      ["moonshotai/Kimi-K2-Instruct"] = { opts = { can_stream = true } },
    }
  end
  _cached_models = models
  _cache_expires = utils.refresh_cache(_cache_file, config.adapters.opts.cache_models_for)
  log:debug("Found %d Hugging Face models", vim.tbl_count(models))
  return models
end

---@class HuggingFace.Adapter: CodeCompanion.Adapter
return {
  name = "huggingface",
  formatted_name = "Hugging Face",
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
    tokens = false,
  },
  url = "https://router.huggingface.co/v1/chat/completions",
  env = {
    api_key = "HUGGINGFACE_API_KEY",
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
      end
      return true
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
      desc = "ID of the model to use from Hugging Face Inference Providers.",
      default = "Qwen/Qwen2.5-32B-Instruct",
      choices = function(adapter)
        return get_models(adapter)
      end,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.5,
      desc = "What sampling temperature to use, between 0 and 2.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 3,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = 4096,
      desc = "The maximum number of tokens to generate.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.7,
      desc = "Nucleus sampling parameter.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    ---@type CodeCompanion.Schema
    stop = {
      order = 5,
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
  },
}
