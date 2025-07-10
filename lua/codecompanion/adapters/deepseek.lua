local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

---@class DeepSeek.Adapter: CodeCompanion.Adapter
return {
  name = "deepseek",
  formatted_name = "DeepSeek",
  roles = {
    llm = "assistant",
    user = "user",
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
    --- Use the OpenAI adapter for the bulk of the work
    setup = function(self)
      return openai.handlers.setup(self)
    end,
    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_tools = function(self, tools)
      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]

      if model_opts.opts and model_opts.opts.can_use_tools == false then
        if tools and vim.tbl_count(tools) > 0 then
          log:warn("Tools are not supported for this model")
        end
        return
      end
      return openai.handlers.form_tools(self, tools)
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      messages = utils.merge_messages(messages)
      messages = utils.merge_system_messages(messages)

      -- Ensure that all messages have a content field
      messages = vim
        .iter(messages)
        :map(function(msg)
          local content = msg.content
          if content and type(content) == "table" then
            msg.content = table.concat(content, "\n")
          elseif not content then
            msg.content = ""
          end
          return msg
        end)
        :totable()

      return { messages = messages }
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param tools? table The table to write any tool output to
    ---@return { status: string, output: { role: string, content: string, reasoning: string? } } | nil
    chat_output = function(self, data, tools)
      local output = {}

      if data and data ~= "" then
        local data_mod = utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok and json.choices and #json.choices > 0 then
          local choice = json.choices[1]
          local delta = (self.opts and self.opts.stream) and choice.delta or choice.message

          if delta then
            output.role = delta.role
            output.content = delta.content

            if delta.reasoning_content then
              output.reasoning = output.reasoning or {}
              output.reasoning.content = delta.reasoning_content
            end

            -- Process tools
            if self.opts.tools and delta.tool_calls and tools then
              for _, tool in ipairs(delta.tool_calls) do
                if self.opts.stream then
                  local index = tool.index
                  local found = false

                  for i, existing_tool in ipairs(tools) do
                    if existing_tool._index == index then
                      tools[i]["function"].arguments = (tools[i]["function"].arguments or "")
                        .. (tool["function"]["arguments"] or "")
                      found = true
                      break
                    end
                  end

                  if not found then
                    table.insert(tools, {
                      ["function"] = {
                        name = tool["function"]["name"],
                        arguments = tool["function"]["arguments"] or "",
                      },
                      id = tool.id,
                      type = "function",
                      _index = index,
                    })
                  end
                else
                  table.insert(tools, {
                    _index = tool.index,
                    ["function"] = {
                      name = tool["function"]["name"],
                      arguments = tool["function"]["arguments"],
                    },
                    id = tool.id,
                    type = "function",
                  })
                end
              end
            end

            return {
              status = "success",
              output = output,
            }
          end
        end
      end
    end,
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    tools = {
      -- Ref: https://api-docs.deepseek.com/guides/function_calling
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
      desc = "ID of the model to use.",
      ---@type string|fun(): string
      default = "deepseek-reasoner",
      choices = {
        ["deepseek-reasoner"] = { opts = { can_reason = true, can_use_tools = false } },
        ["deepseek-chat"] = { opts = { can_use_tools = true } },
      },
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.6,
      desc = "What sampling temperature to use, between 0 and 2. 0.5-0.7 is recommended by DeepSeek for coding tasks.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.95,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both. Not used for R1.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    ---@type CodeCompanion.Schema
    stop = {
      order = 4,
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
      order = 5,
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
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics. Not used for R1",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    frequency_penalty = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim. Not used for R1, but may be specified.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    logprobs = {
      order = 8,
      mapping = "parameters",
      type = "boolean",
      optional = true,
      default = nil,
      desc = "Whether to return log probabilities of the output tokens or not. If true, returns the log probabilities of each output token returned in the content of message. Not supported for R1.",
      subtype_key = {
        type = "integer",
      },
    },
    ---@type CodeCompanion.Schema
    user = {
      order = 9,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = nil,
      desc = "A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. Learn more.",
      validate = function(u)
        return u:len() < 100, "Cannot be longer than 100 characters"
      end,
    },
  },
}
