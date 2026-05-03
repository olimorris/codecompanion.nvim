local openai = require("codecompanion.adapters.http.openai")

---@class CodeCompanion.HTTPAdapter.Kimi: CodeCompanion.HTTPAdapter
return {
  name = "kimi",
  formatted_name = "Kimi",
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
    tokens = true,
  },
  url = "${url}${chat_url}",
  env = {
    url = "https://api.moonshot.ai",
    api_key = "MOONSHOT_API_KEY",
    chat_url = "/v1/chat/completions",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
  },
  handlers = {
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
        self.parameters.stream_options = { include_usage = true }
      end

      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
      end

      return true
    end,

    --- Use the OpenAI adapter for the bulk of the work
    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
    end,
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    ---Format the messages for the request.
    ---
    ---Kimi-k2-thinking rejects assistant messages that contain ``tool_calls``
    ---but no ``reasoning_content`` whenever ``think`` is enabled.  We rewrite
    ---OpenAI's nested ``reasoning`` field into Moonshot's flat
    ---``reasoning_content`` string, and insert an empty-string fallback for
    ---tool-call messages whose original reasoning is unavailable (history that
    ---pre-dates this adapter, edited messages, model swaps).
    ---@param self CodeCompanion.HTTPAdapter
    ---@param messages table
    ---@return table
    form_messages = function(self, messages)
      local result = openai.handlers.form_messages(self, messages)

      local think_on = self.parameters and self.parameters.think == true
      for _, m in ipairs(result.messages or {}) do
        if m.role == self.roles.llm then
          if m.reasoning then
            m.reasoning_content = type(m.reasoning) == "table" and m.reasoning.content or m.reasoning
            m.reasoning = nil
          elseif think_on and m.tool_calls then
            m.reasoning_content = ""
          end
        end
      end

      return result
    end,
    chat_output = function(self, data, tools)
      return openai.handlers.chat_output(self, data, tools)
    end,
    ---Lift streamed ``delta.reasoning_content`` onto the message so it can be
    ---round-tripped on the next turn (see ``form_messages``).
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table
    ---@return table
    parse_message_meta = function(self, data)
      local extra = data.extra
      if extra and extra.reasoning_content then
        data.output.reasoning = { content = extra.reasoning_content }
        if data.output.content == "" then
          data.output.content = nil
        end
      end
      return data
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
      desc = "ID of the Moonshot Kimi model to use. See https://platform.kimi.ai/docs/models.",
      default = "kimi-k2.6",
      choices = {
        -- K2 thinking family (reasoning_content round-trip)
        ["kimi-k2-thinking"] = {
          formatted_name = "Kimi K2 Thinking",
          meta = { context_window = 262144 },
          opts = { can_reason = true },
        },
        ["kimi-k2-thinking-turbo"] = {
          formatted_name = "Kimi K2 Thinking Turbo",
          meta = { context_window = 262144 },
          opts = { can_reason = true },
        },
        -- K2 general
        ["kimi-k2.6"] = {
          formatted_name = "Kimi K2.6",
          meta = { context_window = 262144 },
          opts = { can_reason = true },
        },
        ["kimi-k2.5"] = {
          formatted_name = "Kimi K2.5",
          meta = { context_window = 262144 },
          opts = { can_reason = true },
        },
        ["kimi-k2-turbo-preview"] = {
          formatted_name = "Kimi K2 Turbo Preview",
          meta = { context_window = 262144 },
        },
        ["kimi-k2-0905-preview"] = {
          formatted_name = "Kimi K2 0905 Preview",
          meta = { context_window = 262144 },
        },
        ["kimi-k2-0711-preview"] = {
          formatted_name = "Kimi K2 0711 Preview",
          meta = { context_window = 131072 },
        },
      },
    },
    think = {
      order = 2,
      mapping = "parameters",
      type = "boolean",
      optional = true,
      default = true,
      desc = "Enable thinking mode for k2-thinking-class models. When true, the API streams reasoning_content alongside content; this adapter captures and echoes it back on assistant tool-call messages as Moonshot requires.",
    },
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "What sampling temperature to use, between 0 and 2. Note: kimi-k2-thinking only accepts 1.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.95,
      desc = "Nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both. Note: kimi-k2-thinking only accepts 0.95.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    max_tokens = {
      order = 5,
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
      order = 6,
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
  },
}
