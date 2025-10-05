local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.http.openai")
local tool_utils = require("codecompanion.utils.tool_transformers")
local utils = require("codecompanion.utils.adapters")

---@type string|nil
local response_id

---@class CodeCompanion.HTTPAdapter.OpenAIResponses: CodeCompanion.HTTPAdapter
return {
  name = "openai_responses",
  formatted_name = "OpenAI_Responses",
  roles = {
    llm = "assistant",
    user = "user",
    tool = "tool",
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
  url = "https://api.openai.com/v1/responses",
  env = {
    api_key = "OPENAI_API_KEY",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  handlers = {
    ---@param self CodeCompanion.HTTPAdapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model(self)
      end
      local model_opts = self.schema.model.choices
      if type(model_opts) == "function" then
        model_opts = model_opts(self)
      end

      self.opts.vision = true

      if model_opts and model_opts[model] and model_opts[model].opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts[model].opts)

        if not model_opts[model].opts.has_vision then
          self.opts.vision = false
        end
      end

      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end

      return true
    end,

    ---Set the parameters
    ---@param self CodeCompanion.HTTPAdapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.HTTPAdapter
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      --Ref: https://platform.openai.com/docs/guides/migrate-to-responses?lang=bash

      -- Separate out system messages so they can be sent as instructions
      local instructions = vim
        .iter(messages)
        :filter(function(m)
          return m.role == "system"
        end)
        :map(function(m)
          return m.content
        end)
        :totable()
      local has_instructions = #instructions > 0
      instructions = table.concat(instructions, "\n")

      -- The Responses API is similar to Anthropic in that it has different
      -- message types as their own distinct objects in the messages array

      local input = {}
      local i = 1
      while i <= #messages do
        local m = messages[i]

        if m.role ~= "system" then
          -- Check if this is an image message followed by a text message from the same user
          if m.opts and m.opts.tag == "image" and m.opts.mimetype then
            if self.opts and self.opts.vision then
              local next_msg = messages[i + 1]
              local combined_content = {
                {
                  type = "input_image",
                  image_url = string.format("data:%s;base64,%s", m.opts.mimetype, m.content),
                },
              }

              -- If next message is also from user with text content, combine them
              if next_msg and next_msg.role == m.role and type(next_msg.content) == "string" then
                table.insert(combined_content, {
                  type = "input_text",
                  text = next_msg.content,
                })
                i = i + 1 -- Skip the next message since we've combined it
              end

              table.insert(input, {
                role = m.role,
                content = combined_content,
              })
            end
          elseif m.tool_calls then
            if m.tool_calls then
              m.tool_calls = vim
                .iter(m.tool_calls)
                :map(function(tool_call)
                  return {
                    type = "function_call",
                    id = tool_call.id,
                    call_id = tool_call.call_id,
                    name = tool_call["function"].name,
                    arguments = tool_call["function"].arguments,
                  }
                end)
                :totable()

              for _, tool_call in ipairs(m.tool_calls) do
                table.insert(input, tool_call)
              end
            end
          else
            -- Regular text message
            table.insert(input, {
              role = m.role,
              content = m.content,
            })
          end
        end

        i = i + 1
      end

      return {
        instructions = has_instructions and instructions or nil,
        input = input,
      }
    end,

    ---Provides the schemas of the tools that are available to the LLM to call
    ---@param self CodeCompanion.HTTPAdapter
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
          table.insert(transformed, tool_utils.transform_schema_if_needed(schema))
        end
      end

      return { tools = transformed }
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if json.type == "response.completed" and json.response.usage then
            return json.response.usage.total_tokens
          end
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param tools? table The table to write any tool output to
    ---@return table|nil [status: string, output: table]
    chat_output = function(self, data, tools)
      if not data or data == "" then
        return nil
      end

      -- Handle both streamed data and structured response
      local data_mod = type(data) == "table" and data.body or utils.clean_streamed_data(data)
      local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
      if not ok then
        return nil
      end

      if json.type == "response.created" then
        response_id = json.response.id
      end

      local output = {}
      if json.type == "response.content_part.added" then
        output = {
          role = self.roles.llm,
          content = "\n",
        }
      elseif json.type == "response.output_text.delta" then
        output = {
          role = self.roles.llm,
          content = json.delta,
          meta = { response_id = response_id },
        }
      elseif json.type == "response.output_item.done" and json.item and json.item.type == "function_call" then
        local tool = json.item
        if tools and tool and tool.name and tool.arguments then
          table.insert(tools, {
            _index = json.output_index,
            id = tool.id,
            call_id = tool.call_id,
            type = "function",
            ["function"] = {
              name = tool.name,
              arguments = tool.arguments or "",
            },
          })
        end
      end

      if not output then
        return nil
      end

      return {
        status = "success",
        output = output,
      }
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data string|table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context? table Useful context about the buffer to inline to
    ---@return {status: string, output: table}|nil
    inline_output = function(self, data, context) end,

    tools = {
      ---Format the LLM's tool calls for inclusion back in the request
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table The raw tools collected by chat_output
      ---@return table
      format_tool_calls = function(self, tools)
        return tools
      end,

      ---Output the LLM's tool call so we can include it in the messages
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tool_call {id: string, call_id: string, function: table, name: string}
      ---@param output string
      ---@return table
      output_response = function(self, tool_call, output)
        -- Source: https://platform.openai.com/docs/guides/function-calling?api-mode=chat#handling-function-calls
        return {
          role = self.roles.tool or "tool",
          tool_id = tool_call.id,
          tool_call_id = tool_call.call_id,
          content = output,
          opts = { visible = false },
        }
      end,
    },

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data? table
    ---@return nil
    on_exit = function(self, data)
      response_id = nil
      return openai.handlers.on_exit(self, data)
    end,
  },
  schema = {
    model = openai.schema.model,
    reasoning_effort = openai.schema.reasoning_effort,
    temperature = openai.schema.temperature,
    top_p = openai.schema.top_p,
    stop = openai.schema.stop,
    max_tokens = openai.schema.max_tokens,
    logit_bias = openai.schema.logit_bias,
    user = openai.schema.user,
  },
}
