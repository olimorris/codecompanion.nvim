local log = require("codecompanion.utils.log")
local tokens = require("codecompanion.utils.tokens")
local transform = require("codecompanion.utils.tool_transformers")
local utils = require("codecompanion.utils.adapters")

local input_tokens = 0
local output_tokens = 0

---Remove any keys from the message that are not allowed by the API
---@param message table The message to filter
---@return table The filtered message
local function filter_out_messages(message)
  local allowed = {
    "content",
    "role",
    "reasoning",
    "tool_calls",
  }

  for key, _ in pairs(message) do
    if not vim.tbl_contains(allowed, key) then
      message[key] = nil
    end
  end
  return message
end

---@class Anthropic.Adapter: CodeCompanion.Adapter
return {
  name = "anthropic",
  formatted_name = "Anthropic",
  roles = {
    llm = "assistant",
    user = "user",
  },
  features = {
    tokens = true,
    text = true,
  },
  opts = {
    cache_breakpoints = 4, -- Cache up to this many messages
    cache_over = 300, -- Cache any message which has this many tokens or more
    stream = true,
    tools = true,
    vision = true,
  },
  url = "https://api.anthropic.com/v1/messages",
  env = {
    api_key = "ANTHROPIC_API_KEY",
  },
  headers = {
    ["content-type"] = "application/json",
    ["x-api-key"] = "${api_key}",
    ["anthropic-version"] = "2023-06-01",
    ["anthropic-beta"] = "prompt-caching-2024-07-31",
  },
  temp = {},
  handlers = {
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end

      -- Make sure the individual model options are set
      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
        if not model_opts.opts.has_vision then
          self.opts.vision = false
        end
      end

      -- Add the extended output header if enabled
      if self.temp.extended_output then
        self.headers["anthropic-beta"] = (self.headers["anthropic-beta"] .. "," or "") .. "output-128k-2025-02-19"
      end

      -- Ref: https://docs.anthropic.com/en/docs/build-with-claude/tool-use/token-efficient-tool-use
      if self.opts.has_token_efficient_tools then
        self.headers["anthropic-beta"] = (self.headers["anthropic-beta"] .. "," or "")
          .. "token-efficient-tools-2025-02-19"
      end

      return true
    end,

    ---Set the parameters
    ---@param self CodeCompanion.Adapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      if self.temp.extended_thinking and self.temp.thinking_budget then
        params.thinking = {
          type = "enabled",
          budget_tokens = self.temp.thinking_budget,
        }
      end
      if self.temp.extended_thinking then
        params.temperature = 1
      end

      return params
    end,

    ---Set the format of the role and content for the messages that are sent from the chat buffer to the LLM
    ---@param self CodeCompanion.Adapter
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      local has_tools = false

      -- 1. Extract and format system messages
      local system = vim
        .iter(messages)
        :filter(function(msg)
          return msg.role == "system"
        end)
        :map(function(msg)
          return {
            type = "text",
            text = msg.content,
            cache_control = nil, -- To be set later if needed
          }
        end)
        :totable()
      system = next(system) and system or nil

      -- 2. Remove any system messages from the regular messages
      messages = vim
        .iter(messages)
        :filter(function(msg)
          return msg.role ~= "system"
        end)
        :totable()

      -- 3–7. Clean up, role‐convert, and handle tool calls in one pass
      messages = vim.tbl_map(function(message)
        -- 3. Account for any images
        if message.opts and message.opts.tag == "image" and message.opts.mimetype then
          if self.opts and self.opts.vision then
            message.content = {
              {
                type = "image",
                source = {
                  type = "base64",
                  media_type = message.opts.mimetype,
                  data = message.content,
                },
              },
            }
          else
            -- Remove the message if vision is not supported
            return nil
          end
        end

        -- 4. Remove disallowed keys
        message = filter_out_messages(message)

        -- 5. Turn string content into { { type = "text", text } } and add in the reasoning
        if message.role == self.roles.user or message.role == self.roles.llm then
          -- Anthropic doesn't allow the user to submit an empty prompt. But
          -- this can be necessary to prompt the LLM to analyze any tool
          -- calls and their output
          if message.role == self.roles.user and message.content == "" then
            message.content = "<prompt></prompt>"
          end

          if type(message.content) == "string" then
            message.content = {
              { type = "text", text = message.content },
            }
          end
        end

        if message.tool_calls and vim.tbl_count(message.tool_calls) > 0 then
          has_tools = true
        end

        -- 6. Treat 'tool' role as user
        if message.role == "tool" then
          message.role = self.roles.user
        end

        -- 7. Convert any LLM tool_calls into content blocks
        if has_tools and message.role == self.roles.llm and message.tool_calls then
          message.content = message.content or {}
          for _, call in ipairs(message.tool_calls) do
            table.insert(message.content, {
              type = "tool_use",
              id = call.id,
              name = call["function"].name,
              input = vim.json.decode(call["function"].arguments),
            })
          end
          message.tool_calls = nil
        end

        -- 8. If reasoning is present, format it as a content block
        if message.reasoning and type(message.content) == "table" then
          -- Ref: https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking#how-extended-thinking-works
          table.insert(message.content, 1, {
            type = "thinking",
            thinking = message.reasoning.content,
            signature = message.reasoning._data.signature,
          })
        end

        return message
      end, messages)

      -- 9. Merge consecutive messages with the same role
      messages = utils.merge_messages(messages)

      -- 10. Ensure that any consecutive tool results are merged
      if has_tools then
        for _, m in ipairs(messages) do
          if m.role == self.roles.user and m.content and m.content ~= "" then
            -- Check if content is already an array of blocks
            if type(m.content) == "table" and m.content.type then
              -- If it's a single content block, like a tool_result), make it an array
              m.content = { m.content }
            end

            -- Now we can iterate over the content blocks
            if type(m.content) == "table" and vim.islist(m.content) then
              local consolidated = {}
              for _, block in ipairs(m.content) do
                if block.type == "tool_result" then
                  local prev = consolidated[#consolidated]
                  if prev and prev.type == "tool_result" and prev.tool_use_id == block.tool_use_id then
                    prev.content = prev.content .. block.content
                  else
                    table.insert(consolidated, block)
                  end
                else
                  table.insert(consolidated, block)
                end
              end
              m.content = consolidated
            end
          end
        end
      end

      -- 11+. Cache large messages per opts.cache_over / cache_breakpoints
      local breakpoints_used = 0
      for i = #messages, 1, -1 do
        local msgs = messages[i]
        if msgs.role == self.roles.user then
          -- Loop through the content
          for _, msg in ipairs(msgs.content) do
            if msg.type ~= "text" or msg.text == "" then
              goto continue
            end
            if
              tokens.calculate(msg.text) >= self.opts.cache_over and breakpoints_used < self.opts.cache_breakpoints
            then
              msg.cache_control = { type = "ephemeral" }
              breakpoints_used = breakpoints_used + 1
            end
            ::continue::
          end
        end
      end
      if system and breakpoints_used < self.opts.cache_breakpoints then
        for _, prompt in ipairs(system) do
          if breakpoints_used < self.opts.cache_breakpoints then
            prompt.cache_control = { type = "ephemeral" }
            breakpoints_used = breakpoints_used + 1
          end
        end
      end

      return { system = system, messages = messages }
    end,

    ---Form the reasoning output that is stored in the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The reasoning output from the LLM
    ---@return nil|{ content: string, _data: table }
    form_reasoning = function(self, data)
      local content = vim
        .iter(data)
        :map(function(item)
          return item.content
        end)
        :filter(function(content)
          return content ~= nil
        end)
        :join("")

      local signature = data[#data].signature

      return {
        content = content,
        _data = {
          signature = signature,
        },
      }
    end,

    ---Provides the schemas of the tools that are available to the LLM to call
    ---@param self CodeCompanion.Adapter
    ---@param tools table<string, table>
    ---@return table|nil
    form_tools = function(self, tools)
      if not self.opts.tools or not tools then
        return
      end

      local transformed = {}
      for _, tool in pairs(tools) do
        for _, schema in pairs(tool) do
          table.insert(transformed, transform.to_anthropic(schema))
        end
      end

      return { tools = transformed }
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.Adapter
    ---@param data table The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data then
        if self.opts.stream then
          data = utils.clean_streamed_data(data)
        else
          data = data.body
        end
        local ok, json = pcall(vim.json.decode, data)

        if ok then
          if json.type == "message_start" then
            input_tokens = (json.message.usage.input_tokens or 0)
              + (json.message.usage.cache_creation_input_tokens or 0)

            output_tokens = json.message.usage.output_tokens or 0
          elseif json.type == "message_delta" then
            return (input_tokens + output_tokens + json.usage.output_tokens)
          elseif json.type == "message" then
            return (json.usage.input_tokens + json.usage.output_tokens)
          end
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param tools? table The table to write any tool output to
    ---@return table|nil [status: string, output: table]
    chat_output = function(self, data, tools)
      local output = {}

      if self.opts.stream then
        if type(data) == "string" and string.sub(data, 1, 6) == "event:" then
          return
        end
      end

      if data and data ~= "" then
        if self.opts.stream then
          data = utils.clean_streamed_data(data)
        else
          data = data.body
        end

        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok then
          if json.type == "message_start" then
            output.role = json.message.role
            output.content = ""
          elseif json.type == "content_block_start" then
            if json.content_block.type == "thinking" then
              output.reasoning = output.reasoning or {}
              output.reasoning.content = ""
            end
            if json.content_block.type == "tool_use" and tools then
              -- Source: https://docs.anthropic.com/en/docs/build-with-claude/tool-use/overview#single-tool-example
              table.insert(tools, {
                _index = json.index,
                id = json.content_block.id,
                name = json.content_block.name,
                input = "",
              })
            end
          elseif json.type == "content_block_delta" then
            if json.delta.type == "thinking_delta" then
              output.reasoning = output.reasoning or {}
              output.reasoning.content = json.delta.thinking
            elseif json.delta.type == "signature_delta" then
              output.reasoning = output.reasoning or {}
              output.reasoning.signature = json.delta.signature
            else
              output.content = json.delta.text
              if json.delta.partial_json and tools then
                for i, tool in ipairs(tools) do
                  if tool._index == json.index then
                    tools[i].input = tools[i].input .. json.delta.partial_json
                    break
                  end
                end
              end
            end
          elseif json.type == "message" then
            output.role = json.role

            for i, content in ipairs(json.content) do
              if content.type == "text" then
                output.content = (output.content or "") .. content.text
              elseif content.type == "thinking" then
                output.reasoning = output.reasoning and output.reasoning or {}
                output.reasoning.content = content.text
              elseif content.type == "tool_use" and tools then
                table.insert(tools, {
                  _index = i,
                  id = content.id,
                  name = content.name,
                  -- Encode the input as JSON to match the partial JSON which comes encoded
                  input = vim.json.encode(content.input),
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
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context? table Useful context about the buffer to inline to
    ---@return table|nil
    inline_output = function(self, data, context)
      if self.opts.stream then
        return log:error("Inline output is not supported for non-streaming models")
      end

      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data.body, { luanil = { object = true } })

        if not ok then
          log:error("Error decoding JSON: %s", data.body)
          return { status = "error", output = json }
        end

        if ok then
          if json.type == "message" then
            if json.content[2] then
              return { status = "success", output = json.content[2].text }
            end
            return { status = "success", output = json.content[1].text }
          end
        end
      end
    end,

    tools = {
      ---Format the LLM's tool calls for inclusion back in the request
      ---@param self CodeCompanion.Adapter
      ---@param tools table The raw tools collected by chat_output
      ---@return table|nil
      format_tool_calls = function(self, tools)
        -- Convert to the OpenAI format
        local formatted = {}
        for _, tool in ipairs(tools) do
          local formatted_tool = {
            _index = tool._index,
            id = tool.id,
            type = "function",
            ["function"] = {
              name = tool.name,
              arguments = tool.input,
            },
          }
          table.insert(formatted, formatted_tool)
        end
        return formatted
      end,

      ---Output the LLM's tool call so we can include it in the messages
      ---@param self CodeCompanion.Adapter
      ---@param tool_call {id: string, function: table, name: string}
      ---@param output string
      ---@return table
      output_response = function(self, tool_call, output)
        return {
          -- The role should actually be "user" but we set it to "tool" so that
          -- in the form_messages handler it's easier to identify and merge
          -- with other user messages.
          role = "tool",
          content = {
            type = "tool_result",
            tool_use_id = tool_call.id,
            content = output,
            is_error = false,
          },
          -- Chat Buffer option: To tell the chat buffer that this shouldn't be visible
          opts = { visible = false },
        }
      end,
    },

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.Adapter
    ---@param data? table
    ---@return nil
    on_exit = function(self, data)
      if data and data.status >= 400 then
        log:error("Error %s: %s", data.status, data.body)
      end
    end,
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "The model that will complete your prompt. See https://docs.anthropic.com/claude/docs/models-overview for additional details and options.",
      default = "claude-sonnet-4-20250514",
      choices = {
        ["claude-opus-4-20250514"] = { opts = { can_reason = true, has_vision = true } },
        ["claude-sonnet-4-20250514"] = { opts = { can_reason = true, has_vision = true } },
        ["claude-3-7-sonnet-20250219"] = {
          opts = { can_reason = true, has_vision = true, has_token_efficient_tools = true },
        },
        ["claude-3-5-sonnet-20241022"] = { opts = { has_vision = true } },
        ["claude-3-5-haiku-20241022"] = { opts = { has_vision = true } },
        ["claude-3-opus-20240229"] = { opts = { has_vision = true } },
        "claude-2.1",
      },
    },
    ---@type CodeCompanion.Schema
    extended_output = {
      order = 2,
      mapping = "temp",
      type = "boolean",
      optional = true,
      default = false,
      desc = "Enable larger output context (128k tokens). Only available with claude-3-7-sonnet-20250219.",
      condition = function(self)
        local model = self.schema.model.default
        if self.schema.model.choices[model] and self.schema.model.choices[model].opts then
          return self.schema.model.choices[model].opts.can_reason
        end
        return false
      end,
    },
    ---@type CodeCompanion.Schema
    extended_thinking = {
      order = 3,
      mapping = "temp",
      type = "boolean",
      optional = true,
      desc = "Enable extended thinking for more thorough reasoning. Requires thinking_budget to be set.",
      default = function(self)
        local model = self.schema.model
        if
          model.choices[model.default]
          and model.choices[model.default].opts
          and model.choices[model.default].opts.can_reason == true
        then
          return true
        end
        return false
      end,
      condition = function(self)
        local model = self.schema.model.default
        if self.schema.model.choices[model] and self.schema.model.choices[model].opts then
          return self.schema.model.choices[model].opts.can_reason
        end
        return false
      end,
    },
    ---@type CodeCompanion.Schema
    thinking_budget = {
      order = 4,
      mapping = "temp",
      type = "number",
      optional = true,
      default = 16000,
      desc = "The maximum number of tokens to use for thinking when extended_thinking is enabled. Must be less than max_tokens.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
      condition = function(self)
        local model = self.schema.model.default
        if self.schema.model.choices[model] and self.schema.model.choices[model].opts then
          return self.schema.model.choices[model].opts.can_reason
        end
        return false
      end,
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 5,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = function(self)
        local model = self.schema.model.default
        if
          self.schema.model.choices[model]
          and self.schema.model.choices[model].opts
          and self.schema.model.choices[model].opts.can_reason
        then
          return self.schema.thinking_budget.default + 1000
        end
        return 4096
      end,
      desc = "The maximum number of tokens to generate before stopping. This parameter only specifies the absolute maximum number of tokens to generate. Different models have different maximum values for this parameter.",
      validate = function(n)
        return n > 0 and n <= 128000, "Must be between 0 and 128000"
      end,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Amount of randomness injected into the response. Ranges from 0.0 to 1.0. Use temperature closer to 0.0 for analytical / multiple choice, and closer to 1.0 for creative and generative tasks. Note that even with temperature of 0.0, the results will not be fully deterministic.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1.0"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = nil,
      desc = "Computes the cumulative distribution over all the options for each subsequent token in decreasing probability order and cuts it off once it reaches a particular probability specified by top_p",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    ---@type CodeCompanion.Schema
    top_k = {
      order = 8,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = nil,
      desc = "Only sample from the top K options for each subsequent token. Use top_k to remove long tail low probability responses",
      validate = function(n)
        return n >= 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    stop_sequences = {
      order = 9,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Sequences where the API will stop generating further tokens",
      validate = function(l)
        return #l >= 1, "Must have more than 1 element"
      end,
    },
  },
}
