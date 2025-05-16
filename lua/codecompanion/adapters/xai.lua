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
    tools = true,
  },
  features = {
    text = true,
    tokens = true,
    vision = false,
  },
  url = "${url}${chat_url}",
  env = {
    url = "https://api.x.ai",
    api_key = "XAI_API_KEY",
    chat_url = "/v1/chat/completions",
    models_endpoint = "/v1/models",
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
    ---Provides the schemas of the tools that are available to the LLM to call
    ---@param self CodeCompanion.Adapter
    ---@param tools table<string, table>
    ---@return table|nil
    form_tools = function(self, tools)
      if not self.opts.tools or not tools then
        return
      end
      if vim.tbl_count(tools) == 0 then
        return
      end

      local transformed = {}
      for _, tool in pairs(tools) do
        for _, schema in pairs(tool) do
          ---Remove 'strict' field if it exists to avoid xAI API error
          if schema["function"] and schema["function"].strict then
            schema["function"].strict = nil
          end
          table.insert(transformed, schema)
        end
      end

      return { tools = transformed }
    end, -- Added missing comma here
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
      desc = "See https://docs.x.ai/docs/models for additional details and options.",
      default = "grok-3",
      choices = {
        "grok-3",
        "grok-3-mini",
        "grok-3-fast",
        "grok-2",
      },
    },
  },
}
