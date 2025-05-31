local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")

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
  url = "${url}/models/${model}/v1/chat/completions",
  env = {
    api_key = "HUGGINGFACE_API_KEY",
    url = "https://api-inference.huggingface.co",
    model = "schema.model.default",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  -- NOTE: currently, decided to not implement the tokens counter handle, since the API infernce docs
  -- says it is supported, yet, the usage is returning null when the stream is enabled
  handlers = {
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
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
      desc = "ID of the model to use from Hugging Face.",
      default = "Qwen/Qwen2.5-72B-Instruct",
      choices = {
        "meta-llama/Llama-3.2-1B-Instruct",
        "Qwen/Qwen2.5-72B-Instruct",
        "google/gemma-2-2b-it",
        "mistralai/Mistral-Nemo-Instruct-2407",
      },
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
      default = 2048,
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
    -- caveat to using the cache: https://huggingface.co/docs/api-inference/parameters#caching
    ---@type CodeCompanion.Schema
    ["x-use-cache"] = {
      order = 5,
      mapping = "headers",
      type = "string",
      optional = true,
      default = "true",
      desc = "Whether to use the cache layer on the inference API...",
      choices = { "true", "false" },
    },
    ---@type CodeCompanion.Schema
    ["x-wait-for-model"] = {
      order = 6,
      mapping = "headers",
      type = "string",
      optional = true,
      default = "false",
      desc = "Whether to wait for the model to be loaded...",
      choices = { "true", "false" },
    },
  },
}
