local openai = require("codecompanion.adapters.openai")

---@class Mistral.Adapter: CodeCompanion.Adapter
return {
  name = "mistral",
  formatted_name = "Mistral",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
    vision = true,
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
      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end

      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
        if not model_opts.opts.has_vision then
          self.opts.vision = false
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
      default = "mistral-small-latest",
      choices = {
        -- Premier models
        "mistral-large-latest",
        ["pixtral-large-latest"] = { opts = { has_vision = true } },
        ["mistral-medium-latest"] = { opts = { has_vision = true } },
        "mistral-saba-latest",
        "codestral-latest",
        "ministral-8b-latest",
        "ministral-3b-latest",
        -- Free models, latest
        ["mistral-small-latest"] = { opts = { has_vision = true } },
        ["pixtral-12b-2409"] = { opts = { has_vision = true } },
        -- Free models, research
        "open-mistral-nemo",
        "open-codestral-mamba",
      },
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
