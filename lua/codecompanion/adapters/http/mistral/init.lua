local get_models = require("codecompanion.adapters.http.mistral.get_models")
local openai = require("codecompanion.adapters.http.openai")

---@class CodeCompanion.HTTPAdapter.Mistral: CodeCompanion.HTTPAdapter
return {
  name = "mistral",
  formatted_name = "Mistral",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
    tools = true,
    vision = true,
    cache_adapter = true, -- Cache the resolved adapter to prevent multiple resolutions
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "${url}/v1/chat/completions",
  env = {
    url = "https://api.mistral.ai",
    api_key = "MISTRAL_API_KEY",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
  },
  handlers = {
    setup = function(self)
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model(self)
      end
      local model_opts = self.schema.model.choices
      if type(model_opts) == "function" then
        model_opts = model_opts(self)
      end

      self.opts.vision = false
      self.opts.tools = false

      if model_opts and model_opts[model] and model_opts[model].opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts[model].opts)

        if model_opts[model].opts.has_vision then
          self.opts.vision = true
        end

        if model_opts[model].opts.can_use_tools then
          self.opts.tools = true
        end
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
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
    end,
    chat_output = function(self, data, tools)
      return openai.handlers.chat_output(self, data, tools)
    end,
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return openai.handlers.tools.output_response(self, tool_call, output)
      end,
    },
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
      default = "mistral-small-latest",
      -- default = function(self)
      --   return get_models(self, { last = true })
      -- end,
      choices = function(self, opts)
        return get_models.choices(self, opts)
      end,
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "What sampling temperature to use, we recommend between 0.0 and 0.7. Higher values like 0.7 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 1.5, "Must be between 0 and 1.5"
      end,
    },
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "Nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    max_tokens = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to generate in the completion. The token count of your prompt plus max_tokens cannot exceed the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    stop = {
      order = 5,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Stop generation if this token is detected. Or if one of these tokens is detected when providing an array.",
      validate = function(l)
        return #l >= 1, "Must have more than 1 element"
      end,
    },
    random_seed = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "The seed to use for random sampling. If set, different calls will generate deterministic results.",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    presence_penalty = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Determines how much the model penalizes the repetition of words or phrases. A higher presence penalty encourages the model to use a wider variety of words and phrases, making the output more diverse and creative.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    frequency_penalty = {
      order = 8,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Penalizes the repetition of words based on their frequency in the generated text. A higher frequency penalty discourages the model from repeating words that have already appeared frequently in the output, promoting diversity and reducing repetition.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    n = {
      order = 9,
      mapping = "parameters",
      type = "number",
      default = 1,
      desc = "Number of completions to return for each request, input tokens are only billed once.",
    },
    safe_prompt = {
      order = 10,
      mapping = "parameters",
      type = "boolean",
      optional = true,
      default = false,
      desc = "Whether to inject a safety prompt before all conversations.",
    },
  },
}
