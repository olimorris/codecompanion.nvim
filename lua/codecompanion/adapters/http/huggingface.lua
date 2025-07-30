local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.http.openai")

-- Cache variables for models
local _cached_models
local _cache_expires

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
    return Curl.get(url, {
      sync = true,
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get Hugging Face models from %s. Error: %s", url, response)
    return {}
  end
  local ok2, models_data = pcall(vim.json.decode, response.body)
  if not ok2 then
    log:error("Error parsing Hugging Face models response from %s", url)
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
  _cache_expires = os.time() + (config.adapters.http.opts.cache_models_for or 1800)
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
    tool = "tool",
  },
  opts = {
    stream = true,
    vision = false,
    tools = true,
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
      -- Check if the model supports tools
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model(self)
      end

      local model_opts = self.schema.model.choices
      if type(model_opts) == "function" then
        model_opts = model_opts(self)
      end

      -- Some HF models may not support tools
      if model_opts and model_opts[model] and model_opts[model].opts then
        if model_opts[model].opts.supports_tools == false then
          self.opts.tools = false
        end
        if model_opts[model].opts.has_vision == false then
          self.opts.vision = false
        end
      end

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
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
    end,
    chat_output = function(self, data, tools)
      return openai.handlers.chat_output(self, data, tools)
    end,
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    on_exit = function(self, data)
      return openai.handlers.on_exit(self, data)
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return openai.handlers.tools.output_response(self, tool_call, output)
      end,
    },
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
