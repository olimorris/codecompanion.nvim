local openai = require("codecompanion.adapters.openai")

---@class xAI.Adapter: CodeCompanion.Adapter
return {
  name = "xai",
  formatted_name = "xAI",
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
  url = "https://api.x.ai/v1/chat/completions",
  env = {
    api_key = "XAI_API_KEY",
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
      default = "grok-beta",
      choices = {
        "grok-beta",
      },
    },
  },
}
