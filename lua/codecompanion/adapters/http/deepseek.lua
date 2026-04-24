local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.http.openai")

---@class CodeCompanion.HTTPAdapter.DeepSeek: CodeCompanion.HTTPAdapter
return {
  name = "deepseek",
  formatted_name = "DeepSeek",
  roles = {
    llm = "assistant",
    user = "user",
    tool = "tool",
  },
  opts = {
    stream = true,
    tools = true,
    vision = false,
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "https://api.deepseek.com/chat/completions",
  env = {
    api_key = "DEEPSEEK_API_KEY",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  handlers = {
    lifecycle = {
      ---@param self CodeCompanion.HTTPAdapter
      ---@return boolean
      setup = function(self)
        -- Safely get model and choices (handle function types)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model(self)
        end
        local choices = self.schema.model.choices
        if type(choices) == "function" then
          choices = choices(self)
        end
        local model_opts = choices and choices[model]

        -- Merge model opts
        if model_opts and model_opts.opts then
          self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
        end

        -- Set stream
        if self.opts and self.opts.stream then
          self.parameters.stream = true
          self.parameters.stream_options = { include_usage = true }
        end

        -- When thinking is disabled, don't pass reasoning_effort to the API
        if vim.tbl_get(self.parameters, "thinking", "type") == "disabled" then
          self.parameters.reasoning_effort = nil
        end

        return true
      end,

      on_exit = function(self, data)
        return openai.handlers.on_exit(self, data)
      end,
    },

    request = {
      ---Set the parameters
      ---@param self CodeCompanion.HTTPAdapter
      ---@param params table
      ---@param messages table
      ---@return table
      build_parameters = function(self, params, messages)
        return params
      end,

      ---Set the format of the role and content for the messages from the chat buffer
      ---@param self CodeCompanion.HTTPAdapter
      ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
      ---@return table
      build_messages = function(self, messages)
        messages = adapter_utils.merge_messages(messages, { "tools", "reasoning" })
        messages = adapter_utils.merge_system_messages(messages)

        messages = vim
          .iter(messages)
          :map(function(msg)
            -- Ensure that all messages have a content field
            local content = msg.content
            if vim.islist(content) then
              content = table.concat(content, "\n")
            elseif not content then
              content = ""
            end

            -- Process tool_calls
            local tool_calls = msg.tools
              and msg.tools.calls
              and vim
                .iter(msg.tools.calls)
                :map(function(call)
                  return {
                    _index = call._index,
                    id = call.id,
                    type = call.type,
                    ["function"] = call["function"],
                  }
                end)
                :totable()

            return {
              role = msg.role,
              content = content,
              reasoning_content = msg.role == self.roles.llm and msg.reasoning or nil,
              tool_calls = tool_calls,
              tool_call_id = msg.tools and msg.tools.call_id,
            }
          end)
          :totable()

        return { messages = messages }
      end,

      ---Provides the schemas of the tools that are available to the LLM to call
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table<string, table>
      ---@return table|nil
      build_tools = function(self, tools)
        return openai.handlers.form_tools(self, tools)
      end,

      ---Aggregate reasoning parts into a string
      ---@param self CodeCompanion.HTTPAdapter
      ---@param parts table
      ---@return string
      build_reasoning = function(self, parts)
        return vim
          .iter(parts)
          :map(function(part)
            return part.content
          end)
          :join("")
      end,
    },

    response = {
      ---Output the data from the API ready for insertion into the chat buffer
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
      ---@param tools? table The table to write any tool output to
      ---@return table|nil
      parse_chat = function(self, data, tools)
        return openai.handlers.chat_output(self, data, tools)
      end,

      ---Extract reasoning_content from the response
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table
      ---@return table
      parse_meta = function(self, data)
        local reasoning_content = data.extra and data.extra.reasoning_content
        if reasoning_content then
          data.output.reasoning = { content = reasoning_content }
          -- So that codecompanion doesn't mistake this as a normal response with empty string as the content
          if data.output.content == "" then
            data.output.content = nil
          end
        end
        return data
      end,

      ---Output the data from the API for the inline assistant
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table
      ---@param context table?
      ---@return table|nil
      parse_inline = function(self, data, context)
        return openai.handlers.inline_output(self, data, context)
      end,

      ---Returns the number of tokens generated from the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table
      ---@return number|nil
      parse_tokens = function(self, data)
        return openai.handlers.tokens(self, data)
      end,
    },

    tools = {
      ---Format the tool calls for the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table
      ---@return table
      format_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,

      ---Format the tool response for the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tool_call table
      ---@param output string
      ---@return table
      format_response = function(self, tool_call, output)
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
      desc = "ID of the model to use.",
      ---@type string|fun(): string
      default = "deepseek-v4-flash",
      choices = {
        ["deepseek-v4-flash"] = {
          formatted_name = "DeepSeek V4 Flash",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["deepseek-v4-pro"] = {
          formatted_name = "DeepSeek V4 Pro",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["deepseek-chat"] = {
          formatted_name = "DeepSeek Chat (Deprecated)",
          meta = { context_window = 1048576 },
          opts = { can_use_tools = true },
        },
        ["deepseek-reasoner"] = {
          formatted_name = "DeepSeek Reasoner (Deprecated)",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, can_use_tools = true },
        },
      },
    },
    ---@type CodeCompanion.Schema
    ["thinking.type"] = {
      order = 2,
      mapping = "parameters",
      type = "enum",
      optional = true,
      default = "enabled",
      desc = "Whether to enable thinking mode. 'enabled' turns on reasoning, 'disabled' turns it off.",
      choices = { "enabled", "disabled" },
    },
    ---@type CodeCompanion.Schema
    reasoning_effort = {
      order = 3,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = "max",
      desc = "Constrains effort on reasoning for reasoning models. Only 'high' and 'max' are supported by DeepSeek V4.",
      choices = { "high", "max" },
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 4,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "What sampling temperature to use, between 0 and 2. Not effective when thinking mode is enabled.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 5,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. Not effective when thinking mode is enabled.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    ---@type CodeCompanion.Schema
    stop = {
      order = 6,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Up to 16 sequences where the API will stop generating further tokens.",
      validate = function(l)
        return #l >= 1 and #l <= 16, "Must have between 1 and 16 elements"
      end,
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 7,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = 8192,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    presence_penalty = {
      order = 8,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics. Not effective when thinking mode is enabled.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    frequency_penalty = {
      order = 9,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim. Not effective when thinking mode is enabled.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    logprobs = {
      order = 10,
      mapping = "parameters",
      type = "boolean",
      optional = true,
      default = nil,
      desc = "Whether to return log probabilities of the output tokens or not. If true, returns the log probabilities of each output token returned in the content of message. Not supported for R1.",
      subtype_key = {
        type = "integer",
      },
    },
  },
}
