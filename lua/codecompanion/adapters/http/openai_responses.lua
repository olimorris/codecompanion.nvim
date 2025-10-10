local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.http.openai")
local tool_utils = require("codecompanion.utils.tool_transformers")
local utils = require("codecompanion.utils.adapters")

---@type string|nil
local response_id

---Resolves the options that a model has
---@param adapter CodeCompanion.HTTPAdapter
---@return table
local function resolve_model_opts(adapter)
  local model = adapter.schema.model.default
  local choices = adapter.schema.model.choices
  if type(model) == "function" then
    model = model(adapter)
  end
  if type(choices) == "function" then
    choices = choices(adapter, { async = false })
  end
  return choices[model]
end

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
  parameters = {
    store = false,
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
      local model_opts = resolve_model_opts(self)

      self.opts.vision = true

      if model_opts and model_opts[model] and model_opts[model].opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts[model].opts)

        if not model_opts[model].opts.has_vision then
          self.opts.vision = false
        end
        if not model_opts[model].opts.has_function_calling then
          self.opts.tools = false
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
      local model_opts = resolve_model_opts(self)
      if model_opts and model_opts.opts and model_opts.opts.can_reason then
        params.include = { "reasoning.encrypted_content" }
      end
      return params
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
          -- Reasoning comes first
          if m.reasoning then
            local reasoning_item = {
              type = "reasoning",
            }

            -- Include summary if we have content
            if m.reasoning.content then
              reasoning_item.summary = {
                {
                  type = "summary_text",
                  text = m.reasoning.content,
                },
              }
            end

            -- Include encrypted_content if available (required for stateless mode)
            if m.reasoning.encrypted_content then
              reasoning_item.encrypted_content = m.reasoning.encrypted_content
            end

            table.insert(input, reasoning_item)
          end

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
          elseif m.role == "tool" then
            table.insert(input, {
              type = "function_call_output",
              call_id = m.tool_call_id,
              output = m.content,
            })
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

    ---Form the reasoning output that is stored in the chat buffer
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table The reasoning output from the LLM
    ---@return nil|{ content: string, _data: table }
    form_reasoning = function(self, data)
      local reasoning = {}

      -- Join the content deltas into a single string
      reasoning.content = vim
        .iter(data)
        :map(function(item)
          return item.content
        end)
        :filter(function(content)
          return content ~= nil
        end)
        :join("")

      -- ID and encrypted content appear once, at the end. As we've turned state
      -- off, we need to store the encrypted reasoning tokens
      vim.iter(data):each(function(item)
        if item.id then
          reasoning.id = item.id
        end
        if item.encrypted_content then
          reasoning.encrypted_content = item.encrypted_content
        end
      end)

      if vim.tbl_count(reasoning) == 0 then
        return nil
      end

      return reasoning
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

      -- Handle non-streamed response
      if not self.opts.stream then
        -- Reasoning
        local reasoning = {}
        if json.output then
          for _, item in ipairs(json.output) do
            if item.type == "reasoning" then
              reasoning.id = item.id
              reasoning.encrypted_content = item.encrypted_content
              for _, block in ipairs(item.summary) do
                if block.type == "summary_text" then
                  reasoning.content = reasoning.content and (reasoning.content .. "\n\n" .. block.text) or block.text
                end
              end
            end
          end
        end

        -- Tools
        if json.output and tools then
          local index = 1
          vim
            .iter(json.output)
            :filter(function(item)
              return item.type == "function_call"
            end)
            :each(function(tool)
              table.insert(tools, {
                _index = index,
                id = tool.id,
                call_id = tool.call_id,
                type = "function",
                ["function"] = {
                  name = tool.name,
                  arguments = tool.arguments or "",
                },
              })
              index = index + 1
            end)
        end

        local content = json.output
            and json.output[1]
            and json.output[1].content
            and json.output[1].content[1]
            and json.output[1].content[1].text
          or nil

        return {
          status = "success",
          output = {
            role = self.roles.llm,
            reasoning = reasoning,
            content = content,
          },
        }
      end

      if json.type == "response.created" then
        response_id = json.response.id
      end

      local output = {}
      if json.type == "response.reasoning_summary_text.delta" then
        output = {
          role = self.roles.llm,
          reasoning = { content = json.delta or "" },
          meta = { response_id = response_id },
        }
      elseif json.type == "response.output_text.delta" then
        output = {
          role = self.roles.llm,
          content = json.delta or "",
          meta = { response_id = response_id },
        }
      elseif json.type == "response.completed" then
        if json.response and json.response.output then
          local reasoning = {}
          vim
            .iter(json.response.output)
            :filter(function(reasoning_output)
              return reasoning_output.type == "reasoning"
            end)
            :each(function(reasoning_output)
              reasoning.id = reasoning_output.id
              reasoning.encrypted_content = reasoning_output.encrypted_content
            end)

          vim
            .iter(json.response.output)
            :filter(function(item)
              return item.type == "function_call" and item.status == "completed"
            end)
            :each(function(tool)
              if tools then
                table.insert(tools, {
                  id = tool.id,
                  call_id = tool.call_id,
                  type = "function",
                  ["function"] = {
                    name = tool.name,
                    arguments = tool.arguments or "",
                  },
                })
              end
            end)

          output = {
            role = self.roles.llm,
            reasoning = reasoning,
            meta = {
              response_id = response_id,
            },
          }
        end
      end

      if vim.tbl_count(output) == 0 then
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

        if json.output then
          local content = json.output
              and json.output[1]
              and json.output[1].content
              and json.output[1].content[1]
              and json.output[1].content[1].text
            or nil
          return { status = "success", output = content }
        end
      end
    end,

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
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      ---@type string|fun(): string
      default = "gpt-5-2025-08-07",
      choices = {
        ["gpt-5-2025-08-07"] = {
          formatted_name = "GPT-5",
          opts = { has_function_calling = true, has_vision = true, can_reason = true },
        },
        ["codex-mini-latest"] = {
          formatted_name = "Codex-mini",
          opts = { has_function_calling = true, has_vision = true, can_reason = true },
        },
        ["gpt-5-codex"] = {
          formatted_name = "GPT-5 Codex",
          opts = { has_function_calling = true, has_vision = true, can_reason = true },
        },
        ["gpt-5-chat-latest"] = {
          formatted_name = "GPT-5 Chat",
          opts = { has_function_calling = true, has_vision = true },
        },
        ["gpt-5-pro-2025-10-06"] = {
          formatted_name = "GPT-5 Pro",
          opts = { has_function_calling = true, has_vision = true, can_reason = true, stream = false },
        },
        ["o4-mini-deep-research-2025-06-26"] = {
          formatted_name = "o4-mini-deep-research",
          opts = { has_function_calling = false, has_vision = true, can_reason = true },
        },
        ["o3-deep-research-2025-06-26"] = {
          formatted_name = "o3-deep-research",
          opts = { has_function_calling = false, has_vision = true, can_reason = true },
        },
        ["o3-pro-2025-06-10"] = {
          formatted_name = "o3-pro",
          opts = { has_function_calling = false, has_vision = true, can_reason = true, stream = false },
        },
        ["o1-pro-2025-03-19"] = {
          formatted_name = "o1-pro",
          opts = { has_function_calling = true, has_vision = true, can_reason = true, stream = false },
        },
      },
    },
    ["reasoning.effort"] = {
      order = 2,
      mapping = "parameters",
      type = "string",
      optional = true,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        local choices = self.schema.model.choices
        if type(choices) == "function" then
          choices = choices(self)
        end
        if choices and choices[model] and choices[model].opts and choices[model].opts.can_reason then
          return true
        end
        return false
      end,
      default = "medium",
      desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.",
      choices = {
        "high",
        "medium",
        "low",
        "minimal",
      },
    },
    ["reasoning.summary"] = {
      order = 3,
      mapping = "parameters",
      type = "string",
      optional = true,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        local choices = self.schema.model.choices
        if type(choices) == "function" then
          choices = choices(self)
        end
        if choices and choices[model] and choices[model].opts and choices[model].opts.can_reason then
          return true
        end
        return false
      end,
      default = "auto",
      desc = "A summary of the reasoning performed by the model. This can be useful for debugging and understanding the model's reasoning process.",
      choices = {
        "auto",
        "concise",
        "detailed",
      },
    },
    temperature = {
      order = 4,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_logprobs = {
      order = 5,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = nil,
      desc = "An integer between 0 and 20 specifying the number of most likely tokens to return at each token position, each with an associated log probability.",
      validate = function(n)
        return n >= 0 and n <= 20, "Must be between 0 and 20"
      end,
    },
    top_p = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    max_output_tokens = {
      order = 7,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
  },
}
