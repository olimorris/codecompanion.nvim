local openai = require("codecompanion.adapters.openai")

---@class Gemini.Adapter: CodeCompanion.Adapter
return {
  name = "gemini",
  formatted_name = "Gemini",
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
  url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
  env = {
    api_key = "GEMINI_API_KEY",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
  },
  handlers = {
    setup = function(self)
      -- Make sure the individual model options are set
      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
        if not model_opts.opts.has_vision then
          self.opts.vision = false
        end
      end

      if self.opts and self.opts.stream then
        self.parameters = self.parameters or {}
        self.parameters.stream = true
        self.parameters.stream_options = { include_usage = true }
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
      -- Gemini does not support system messages, so we need to prepend the content
      local formatted = openai.handlers.form_messages(self, messages)
      local formatted_messages = formatted.messages

      local system_message = vim.iter(formatted_messages):find(function(msg)
        return msg.role == "system"
      end)

      if not system_message then
        return formatted
      end

      local system_content = system_message.content

      local other_messages = vim
        .iter(formatted_messages)
        :filter(function(msg)
          return msg.role ~= "system"
        end)
        :totable()

      local first_user_message = vim.iter(other_messages):find(function(msg)
        return msg.role == self.roles.user
      end)

      if first_user_message then
        -- Prepend system content to the first user message
        if type(first_user_message.content) == "string" and type(system_content) == "string" then
          first_user_message.content = system_content .. "\n\n" .. first_user_message.content
        elseif type(first_user_message.content) == "table" then
          -- Handle multipart (vision) messages by adding system prompt as first text part
          table.insert(first_user_message.content, 1, { type = "text", text = system_content })
        end
      else
        -- If no user message, add system message as a user message at the beginning
        table.insert(other_messages, 1, { role = self.roles.user, content = system_content })
      end

      formatted.messages = other_messages
      return formatted
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
      desc = "The model that will complete your prompt. See https://ai.google.dev/gemini-api/docs/models/gemini#model-variations for additional details and options.",
      default = "gemini-2.5-flash",
      choices = {
        ["gemini-2.5-pro"] = { opts = { can_reason = true, has_vision = true } },
        ["gemini-2.5-flash"] = { opts = { can_reason = true, has_vision = true } },
        ["gemini-2.5-flash-preview-05-20"] = { opts = { can_reason = true, has_vision = true } },
        ["gemini-2.0-flash"] = { opts = { has_vision = true } },
        ["gemini-2.0-flash-lite"] = { opts = { has_vision = true } },
        ["gemini-1.5-pro"] = { opts = { has_vision = true } },
        ["gemini-1.5-flash"] = { opts = { has_vision = true } },
      },
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 2,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to include in a response candidate. Note: The default value varies by model",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = nil,
      desc = "Controls the randomness of the output.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum cumulative probability of tokens to consider when sampling. The model uses combined Top-k and Top-p (nucleus) sampling. Tokens are sorted based on their assigned probabilities so that only the most likely tokens are considered. Top-k sampling directly limits the maximum number of tokens to consider, while Nucleus sampling limits the number of tokens based on the cumulative probability.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    reasoning_effort = {
      order = 5,
      mapping = "parameters",
      type = "string",
      optional = true,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        if self.schema.model.choices[model] and self.schema.model.choices[model].opts then
          return self.schema.model.choices[model].opts.can_reason
        end
        return false
      end,
      default = "medium",
      desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.",
      choices = {
        "high",
        "medium",
        "low",
        "none",
      },
    },
  },
}
