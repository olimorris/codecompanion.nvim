---Source: https://ai.google.dev/gemini-api/docs/interactions-overview

local adapter_utils = require("codecompanion.adapters.utils")
local log = require("codecompanion.utils.log")
local tags = require("codecompanion.interactions.shared.tags")
local tool_transformer = require("codecompanion.adapters.utils.tool_transformers")

---Track the step type at each stream index so a `step.delta` event knows whether it belongs to a thought or a model_output
---@type table<number, string>
local step_types = {}

---Extract the first complete JSON object from a potentially concatenated string
---Workaround for Gemini bug where multiple JSON objects get concatenated
---Ref: #2620
---@param args string
---@return string
local function fix_concatenated_args(args)
  local ok = pcall(vim.json.decode, args)
  if ok then
    return args
  end

  local depth = 0
  local escaped = false
  local in_string = false

  for i = 1, #args do
    local char = args:sub(i, i)

    if escaped then
      escaped = false
    elseif char == "\\" and in_string then
      escaped = true
    elseif char == '"' then
      in_string = not in_string
    elseif not in_string then
      if char == "{" then
        depth = depth + 1
      elseif char == "}" then
        depth = depth - 1
        if depth == 0 and i < #args then
          return args:sub(1, i)
        end
      end
    end
  end

  return args
end

---Decode a JSON arguments string to a table, applying concatenation fix
---@param args string|table
---@return table
local function decode_args(args)
  if type(args) == "table" then
    return args
  end
  if type(args) ~= "string" or args == "" then
    return {}
  end

  args = fix_concatenated_args(args)
  local ok, decoded = pcall(vim.json.decode, args)
  if ok then
    return decoded
  end
  return {}
end

---Join the `text` blocks of a content/summary array into a single string
---@param blocks? table
---@return string|nil
local function join_text_blocks(blocks)
  local text
  for _, block in ipairs(blocks or {}) do
    if block.type == "text" then
      text = (text or "") .. block.text
    end
  end
  return text
end

---@class CodeCompanion.HTTPAdapter.GeminiInteractions: CodeCompanion.HTTPAdapter
return {
  name = "gemini_interactions",
  vendor = "gemini",
  formatted_name = "Gemini_Interactions",
  roles = {
    llm = "model",
    user = "user",
  },
  features = {
    text = true,
    tokens = true,
  },
  opts = {
    documents = true,
    stream = true,
    tools = true,
    vision = true,
  },
  url = "https://generativelanguage.googleapis.com/v1beta/interactions${stream}",
  env = {
    api_key = "GEMINI_API_KEY",
    stream = function(self)
      if self.opts.stream then
        return "?alt=sse"
      end
      return ""
    end,
  },
  headers = {
    ["Content-Type"] = "application/json",
    ["x-goog-api-key"] = "${api_key}",
  },
  parameters = {
    -- Use the stateless endpoint
    store = false,
  },
  available_tools = {
    ["web_search"] = {
      description = "Allows the model to search the web via Google Search for the latest information before generating a response.",
      ---@param self CodeCompanion.HTTPAdapter.GeminiInteractions
      ---@param meta { tools: table }
      callback = function(self, meta)
        table.insert(meta.tools, {
          type = "google_search",
        })
      end,
    },
  },
  handlers = {
    lifecycle = {
      ---@param self CodeCompanion.HTTPAdapter
      ---@return boolean
      setup = function(self)
        local model_opts = adapter_utils.model_choice(self)

        self.opts.vision = true

        if model_opts and model_opts.opts then
          self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
          if not model_opts.opts.has_vision then
            self.opts.vision = false
          end
        end

        if self.opts and self.opts.stream then
          self.parameters.stream = true
        end

        return true
      end,

      ---Function to run when the request has completed
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data? table
      ---@return nil
      on_exit = function(self, data)
        step_types = {}
        if data and data.status and data.status >= 400 then
          log:error("Error: %s", data.body)
        end
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
      ---@param messages table
      ---@return table
      build_messages = function(self, messages)
        local system_parts = {}
        local input = {}
        local i = 1

        while i <= #messages do
          local m = messages[i]

          if m.role == "system" then
            table.insert(system_parts, m.content)

          -- Tool result -> function_result
          -- https://ai.google.dev/gemini-api/docs/interactions-overview
          elseif m.role == "tool" and m.tools then
            local content = m.content
            if type(content) ~= "string" then
              content = vim.json.encode(content)
            end

            table.insert(input, {
              type = "function_result",
              name = m.tools.name,
              call_id = m.tools.call_id,
              result = { { type = "text", text = content } },
            })

          -- Image -> a user_input turn containing an image content part
          elseif m._meta and m._meta.tag == tags.IMAGE and m.context and m.context.mimetype then
            if self.opts and self.opts.vision then
              local parts = {
                { type = "image", data = m.content, mime_type = m.context.mimetype },
              }

              -- Combine with the following text message from the same user turn
              local next_msg = messages[i + 1]
              if
                next_msg
                and next_msg.role == m.role
                and type(next_msg.content) == "string"
                and not (next_msg._meta and next_msg._meta.tag == tags.IMAGE)
              then
                table.insert(parts, { type = "text", text = next_msg.content })
                i = i + 1
              end

              table.insert(input, { type = "user_input", content = parts })
            end

          -- Document (PDF only) -> a user_input turn containing a document content part
          elseif
            m._meta
            and m._meta.tag == tags.DOCUMENT
            and m._meta.filetype == "pdf"
            and m.context
            and m.context.mimetype
          then
            if self.opts and self.opts.documents then
              local parts = {
                { type = "document", data = m.content, mime_type = m.context.mimetype },
              }

              -- Combine with the following text message from the same user turn
              local next_msg = messages[i + 1]
              if
                next_msg
                and next_msg.role == m.role
                and type(next_msg.content) == "string"
                and not (next_msg._meta and next_msg._meta.tag == tags.DOCUMENT)
              then
                table.insert(parts, { type = "text", text = next_msg.content })
                i = i + 1
              end

              table.insert(input, { type = "user_input", content = parts })
            else
              log:warn(
                "The `%s` model does not support documents so has been removed from the request",
                self.formatted_name
              )
            end

          -- LLM turn -> thought, model_output and function_call steps
          elseif m.role == self.roles.llm then
            if m.reasoning and (m.reasoning.content or m.reasoning.signature) then
              table.insert(input, {
                type = "thought",
                signature = m.reasoning.signature,
                summary = m.reasoning.content and { { type = "text", text = m.reasoning.content } } or nil,
              })
            end

            if m.content and m.content ~= "" then
              table.insert(input, {
                type = "model_output",
                content = { { type = "text", text = m.content } },
              })
            end

            if m.tools and m.tools.calls then
              for _, call in ipairs(m.tools.calls) do
                table.insert(input, {
                  type = "function_call",
                  id = call.id,
                  name = call["function"].name,
                  arguments = decode_args(call["function"].arguments),
                  signature = call.signature,
                })
              end
            end

          -- Regular user turn
          else
            table.insert(input, { type = "user_input", content = m.content })
          end

          i = i + 1
        end

        local result = { input = input }

        if #system_parts > 0 then
          result.system_instruction = table.concat(system_parts, "\n\n")
        end

        return result
      end,

      ---Provides the schemas of the tools that are available to the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table<string, table>
      ---@return table|nil
      build_tools = function(self, tools)
        if not self.opts.tools or not tools then
          return nil
        end
        if vim.tbl_count(tools) == 0 then
          return nil
        end

        local transformed = {}
        for _, tool in pairs(tools) do
          for _, schema in pairs(tool) do
            if schema._meta and schema._meta.adapter_tool then
              if self.available_tools[schema.name] then
                self.available_tools[schema.name].callback(self, { tools = transformed })
              end
            else
              table.insert(transformed, tool_transformer.to_gemini_interactions(schema))
            end
          end
        end

        return { tools = transformed }
      end,

      ---Form the structured output schema for the request body
      ---@param self CodeCompanion.HTTPAdapter
      ---@param schema CodeCompanion.StructuredOutput.Schema
      ---@return table|nil
      build_structured_output = function(self, schema)
        if not schema then
          return
        end
        if not self.opts.can_form_structured_outputs then
          return log:warn("Model `%s` does not support structured outputs", self.model and self.model.name)
        end
        return require("codecompanion.adapters.utils.structured_outputs").to_gemini_interactions(schema)
      end,

      ---Form the reasoning output that is stored in the chat buffer
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table The reasoning output from the LLM
      ---@return nil|{ content: string, signature: string }
      build_reasoning = function(self, data)
        local content = vim
          .iter(data)
          :map(function(item)
            return item.content
          end)
          :filter(function(item_content)
            return item_content ~= nil
          end)
          :join("")

        local signature
        for _, item in ipairs(data) do
          if item.signature then
            signature = (signature or "") .. item.signature
          end
        end

        if content == "" and not signature then
          return nil
        end

        return {
          content = content ~= "" and content or nil,
          signature = signature,
        }
      end,
    },

    response = {
      ---Returns the number of tokens generated from the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data string|table The data from the LLM
      ---@return number|nil
      parse_tokens = function(self, data)
        if not data or data == "" then
          return nil
        end

        if not self.opts.stream then
          local data_mod = type(data) == "table" and data.body or data
          local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
          if ok and json.usage then
            return json.usage.total_tokens
          end
          return nil
        end

        local data_mod = adapter_utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
        if ok and json.event_type == "interaction.completed" and json.interaction and json.interaction.usage then
          return json.interaction.usage.total_tokens
        end
      end,

      ---Output the data from the API ready for insertion into the chat buffer
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data string|table The streamed or non-streamed data from the API
      ---@param tools? table The table to write any tool output to
      ---@return table|nil
      parse_chat = function(self, data, tools)
        if not data or data == "" then
          return nil
        end

        if not self.opts.stream then
          local data_mod = type(data) == "table" and data.body or data
          local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
          if not ok or not json.steps then
            return nil
          end

          local reasoning = {}
          local content
          local tool_index = 0

          for _, step in ipairs(json.steps) do
            if step.type == "thought" then
              reasoning.content = join_text_blocks(step.summary)
              reasoning.signature = step.signature
            elseif step.type == "model_output" then
              content = (content or "") .. (join_text_blocks(step.content) or "")
            elseif step.type == "function_call" and tools then
              tool_index = tool_index + 1
              table.insert(tools, {
                _index = tool_index,
                id = step.id,
                name = step.name,
                args = step.arguments,
                signature = step.signature,
              })
            end
          end

          return {
            status = "success",
            output = {
              content = content,
              reasoning = next(reasoning) and reasoning or nil,
              role = self.roles.llm,
            },
          }
        end

        local data_mod = adapter_utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
        if not ok then
          return nil
        end

        if json.event_type == "step.start" and json.step then
          step_types[json.index] = json.step.type

          if json.step.type == "thought" then
            local summary = join_text_blocks(json.step.summary)
            local signature = json.step.signature and json.step.signature ~= "" and json.step.signature or nil
            if not summary and not signature then
              return nil
            end
            return {
              status = "success",
              output = { role = self.roles.llm, reasoning = { content = summary, signature = signature } },
            }
          elseif json.step.type == "model_output" then
            local content = join_text_blocks(json.step.content)
            if not content then
              return nil
            end
            return { status = "success", output = { role = self.roles.llm, content = content } }
          elseif json.step.type == "function_call" and tools then
            -- The `arguments` field is only ever a placeholder (typically `{}`) at
            -- step.start; the real arguments arrive as a JSON-encoded string via a
            -- later `arguments_delta` step.delta event
            local initial_args = type(json.step.arguments) == "table"
                and next(json.step.arguments)
                and vim.json.encode(json.step.arguments)
              or nil

            table.insert(tools, {
              _index = json.index,
              id = json.step.id,
              name = json.step.name,
              args = initial_args,
              signature = json.step.signature,
            })
          end
          return nil
        end

        if json.event_type == "step.delta" and json.delta then
          local step_type = step_types[json.index]

          if json.delta.type == "thought_signature" then
            return {
              status = "success",
              output = { role = self.roles.llm, reasoning = { signature = json.delta.signature } },
            }
          elseif json.delta.type == "thought_summary" then
            local text = json.delta.content and json.delta.content.text
            if not text then
              return nil
            end
            return { status = "success", output = { role = self.roles.llm, reasoning = { content = text } } }
          elseif json.delta.type == "text" then
            if step_type == "thought" then
              return {
                status = "success",
                output = { role = self.roles.llm, reasoning = { content = json.delta.text } },
              }
            end
            return { status = "success", output = { role = self.roles.llm, content = json.delta.text } }
          elseif json.delta.type == "arguments_delta" and tools then
            for _, tool in ipairs(tools) do
              if tool._index == json.index then
                tool.args = (tool.args or "") .. (json.delta.arguments or "")
                break
              end
            end
          end
          return nil
        end

        return nil
      end,

      ---Output the data from the API ready for inlining into the current buffer
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data string|table
      ---@param context? table
      ---@return table|nil
      parse_inline = function(self, data, context)
        if self.opts.stream then
          return log:error("Inline output is not supported in streaming mode")
        end

        if data and data ~= "" then
          local ok, json = pcall(vim.json.decode, data.body, { luanil = { object = true } })

          if not ok then
            log:error("Error decoding JSON: %s", data.body)
            return { status = "error", output = json }
          end

          local content
          for _, step in ipairs(json.steps or {}) do
            if step.type == "model_output" then
              content = (content or "") .. (join_text_blocks(step.content) or "")
            end
          end

          if content then
            return { status = "success", output = content }
          end
        end
      end,
    },

    tools = {
      ---Normalize raw tool calls from parse_chat into the internal format
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table
      ---@return table
      format_calls = function(self, tools)
        local formatted = {}
        for _, tool in ipairs(tools) do
          table.insert(formatted, {
            _index = tool._index,
            id = tool.id or string.format("call_%s_%d", os.time(), tool._index),
            signature = tool.signature,
            type = "function",
            ["function"] = {
              arguments = type(tool.args) == "table" and vim.json.encode(tool.args)
                or (tool.args and tool.args ~= "" and tool.args or "{}"),
              name = tool.name,
            },
          })
        end
        return formatted
      end,

      ---Format the tool response for inclusion in messages
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tool_call table
      ---@param output string
      ---@return table
      format_response = function(self, tool_call, output)
        return {
          content = output,
          opts = { visible = false },
          role = "tool",
          tools = {
            call_id = tool_call.id,
            name = tool_call["function"].name,
          },
        }
      end,
    },
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "The model that will complete your prompt. See https://ai.google.dev/gemini-api/docs/models/gemini for details.",
      default = "gemini-3.1-pro-preview",
      choices = {
        -- Gemini 3
        ["gemini-3.1-pro-preview"] = {
          formatted_name = "Gemini 3.1 Pro",
          meta = { context_window = 1048576 },
          opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
        },
        ["gemini-3.5-flash"] = {
          formatted_name = "Gemini 3.5 Flash",
          meta = { context_window = 1048576 },
          opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
        },
        ["gemini-3.1-flash-lite-preview"] = {
          formatted_name = "Gemini 3.1 Flash Lite",
          meta = { context_window = 1048576 },
          opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
        },
        ["gemini-3-flash-preview"] = {
          formatted_name = "Gemini 3 Flash",
          meta = { context_window = 1048576 },
          opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
        },

        -- Gemini 2.5
        ["gemini-2.5-pro"] = {
          formatted_name = "Gemini 2.5 Pro",
          meta = { context_window = 1048576 },
          opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
        },
        ["gemini-2.5-flash"] = {
          formatted_name = "Gemini 2.5 Flash",
          meta = { context_window = 1048576 },
          opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
        },
        ["gemini-2.5-flash-lite"] = {
          formatted_name = "Gemini 2.5 Flash Lite",
          meta = { context_window = 1048576 },
          opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
        },
      },
    },
    max_output_tokens = {
      order = 2,
      mapping = "body.generation_config",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to include in a response candidate. Note: The default value varies by model.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    temperature = {
      order = 3,
      mapping = "body.generation_config",
      type = "number",
      optional = true,
      default = nil,
      desc = "Controls the randomness of the output.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 4,
      mapping = "body.generation_config",
      type = "number",
      optional = true,
      default = nil,
      desc = "The maximum cumulative probability of tokens to consider when sampling.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    top_k = {
      order = 5,
      mapping = "body.generation_config",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to consider when sampling.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    thinking_level = {
      order = 6,
      mapping = "body.generation_config",
      type = "string",
      optional = true,
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      enabled = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        local choice = self.schema.model.choices[model]
        if type(choice) == "table" and choice.opts then
          return choice.opts.can_reason or false
        end
        return false
      end,
      default = "high",
      desc = "Controls thinking effort for reasoning models. See https://ai.google.dev/gemini-api/docs/thinking.",
      choices = {
        "high",
        "medium",
        "low",
        "none",
      },
    },
    thinking_summaries = {
      order = 7,
      mapping = "body.generation_config",
      type = "string",
      optional = true,
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      enabled = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        local choice = self.schema.model.choices[model]
        if type(choice) == "table" and choice.opts then
          return choice.opts.can_reason or false
        end
        return false
      end,
      default = "auto",
      desc = "Controls whether a summary of the model's thinking is returned. See https://ai.google.dev/gemini-api/docs/thinking.",
    },
    presence_penalty = {
      order = 8,
      mapping = "body.generation_config",
      type = "number",
      optional = true,
      default = nil,
      desc = "Presence penalty applied to the next token's logprobs if the token has already been seen in the response.",
    },
    frequency_penalty = {
      order = 9,
      mapping = "body.generation_config",
      type = "number",
      optional = true,
      default = nil,
      desc = "Frequency penalty applied to the next token's logprobs, multiplied by the number of times each token has been seen in the response so far.",
    },
  },
}
