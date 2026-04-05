---Source: https://ai.google.dev/gemini-api/docs

local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")
local transform = require("codecompanion.utils.tool_transformers")

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

---@class CodeCompanion.HTTPAdapter.Gemini: CodeCompanion.HTTPAdapter
return {
  name = "gemini",
  formatted_name = "Gemini",
  roles = {
    llm = "model",
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
  url = "https://generativelanguage.googleapis.com/v1beta/models/${model}${stream}key=${api_key}",
  env = {
    api_key = "GEMINI_API_KEY",
    model = "schema.model.default",
    stream = function(self)
      if self.opts.stream then
        return ":streamGenerateContent?alt=sse&"
      end
      return ":generateContent?"
    end,
  },
  headers = {
    ["Content-Type"] = "application/json",
  },
  parameters = {},
  handlers = {
    ---@param self CodeCompanion.HTTPAdapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model(self)
      end

      self.opts.vision = true

      local choices = self.schema.model.choices
      if type(choices) == "table" and choices[model] and type(choices[model]) == "table" then
        if choices[model].opts then
          self.opts = vim.tbl_deep_extend("force", self.opts, choices[model].opts)
          if not choices[model].opts.has_vision then
            self.opts.vision = false
          end
        end
      end

      return true
    end,

    ---@param self CodeCompanion.HTTPAdapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.HTTPAdapter
    ---@param messages table
    ---@return table
    form_messages = function(self, messages)
      -- Collect system instructions into a single system_instruction
      -- https://ai.google.dev/gemini-api/docs/text-generation#system-instructions
      local system_parts = {}
      local contents = {}

      for _, msg in ipairs(messages) do
        if msg.role == "system" then
          table.insert(system_parts, { text = msg.content })

        -- Tool result -> functionResponse
        -- https://ai.google.dev/gemini-api/docs/function-calling?example=meeting#multimodal
        elseif msg.role == "tool" and msg.tools then
          local response_content = msg.content
          if type(response_content) == "string" then
            local ok, decoded = pcall(vim.json.decode, response_content)
            if not ok then
              decoded = { result = response_content }
            end
            response_content = decoded
          end

          table.insert(contents, {
            role = self.roles.user,
            parts = {
              {
                functionResponse = {
                  id = msg.tools.call_id,
                  name = msg.tools.name,
                  response = response_content,
                },
              },
            },
          })

        -- LLM message with tool calls -> functionCall parts
        -- https://ai.google.dev/gemini-api/docs/function-calling?example=meeting#how-it-works
        elseif msg.tools and msg.tools.calls then
          local parts = {}

          if msg.content and msg.content ~= "" then
            table.insert(parts, { text = msg.content })
          end

          for _, call in ipairs(msg.tools.calls) do
            local part = {
              functionCall = {
                args = decode_args(call["function"].arguments),
                id = call.id,
                name = call["function"].name,
              },
            }
            if call.thought_signature then
              part.thoughtSignature = call.thought_signature
            end
            table.insert(parts, part)
          end

          table.insert(contents, {
            role = self.roles.llm,
            parts = parts,
          })

        -- Image -> inline_data
        -- https://ai.google.dev/gemini-api/docs/image-understanding#inline-image
        elseif msg._meta and msg._meta.tag == "image" and msg.context and msg.context.mimetype then
          if self.opts and self.opts.vision then
            table.insert(contents, {
              role = msg.role == self.roles.llm and self.roles.llm or self.roles.user,
              parts = {
                {
                  inline_data = {
                    data = msg.content,
                    mime_type = msg.context.mimetype,
                  },
                },
              },
            })
          end

        -- Regular text message
        -- https://ai.google.dev/gemini-api/docs/text-generation
        else
          table.insert(contents, {
            role = msg.role,
            parts = {
              { text = msg.content },
            },
          })
        end
      end

      -- Merge consecutive user messages that contain functionResponse parts
      local merged = {}
      for _, entry in ipairs(contents) do
        local prev = merged[#merged]
        if
          prev
          and prev.role == self.roles.user
          and entry.role == self.roles.user
          and prev.parts[1]
          and prev.parts[1].functionResponse
          and entry.parts[1]
          and entry.parts[1].functionResponse
        then
          for _, part in ipairs(entry.parts) do
            table.insert(prev.parts, part)
          end
        else
          table.insert(merged, entry)
        end
      end

      local result = { contents = merged }

      if #system_parts > 0 then
        result.system_instruction = {
          parts = system_parts,
          role = self.roles.user,
        }
      end

      return result
    end,

    ---Provides the schemas of the tools that are available to the LLM
    ---@param self CodeCompanion.HTTPAdapter
    ---@param tools table<string, table>
    ---@return table|nil
    form_tools = function(self, tools)
      if not self.opts.tools or not tools then
        return nil
      end
      if vim.tbl_count(tools) == 0 then
        return nil
      end

      -- https://ai.google.dev/gemini-api/docs/function-calling

      local declarations = {}
      for _, tool in pairs(tools) do
        for _, schema in pairs(tool) do
          table.insert(declarations, transform.to_gemini(schema))
        end
      end

      return {
        tools = {
          { functionDeclarations = declarations },
        },
      }
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data string The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data and data ~= "" then
        data = adapter_utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok and json.usageMetadata then
          local tokens = json.usageMetadata.totalTokenCount
          log:trace("Tokens: %s", tokens)
          return tokens
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data string|table The streamed or non-streamed data from the API
    ---@param tools? table The table to write any tool output to
    ---@return table|nil
    chat_output = function(self, data, tools)
      if not data or data == "" then
        return nil
      end

      local data_mod
      if type(data) == "table" then
        data_mod = data.body
      else
        data_mod = adapter_utils.clean_streamed_data(data)
      end

      local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
      if not ok or not json.candidates or #json.candidates == 0 then
        return nil
      end

      local candidate = json.candidates[1]
      if not candidate.content then
        return nil
      end

      local text_content = ""
      local tool_index = 0

      for _, part in ipairs(candidate.content.parts or {}) do
        -- Skip thought parts
        if part.thought then
          goto next_part
        end

        if part.text then
          text_content = text_content .. part.text
        end

        if part.functionCall and self.opts.tools and tools then
          tool_index = tool_index + 1
          table.insert(tools, {
            _index = tool_index,
            args = part.functionCall.args,
            id = part.functionCall.id,
            name = part.functionCall.name,
            thought_signature = part.thoughtSignature, -- https://ai.google.dev/gemini-api/docs/thought-signatures#function-calling
          })
        end

        ::next_part::
      end

      return {
        status = "success",
        output = {
          content = text_content ~= "" and text_content or nil,
          role = "llm",
        },
      }
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data string|table
    ---@param context? table
    ---@return table|nil
    inline_output = function(self, data, context)
      if self.opts.stream then
        return log:error("Inline output is not supported in streaming mode")
      end

      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data.body, { luanil = { object = true } })

        if not ok then
          log:error("Error decoding JSON: %s", data.body)
          return { status = "error", output = json }
        end

        local text = json.candidates[1].content.parts[1].text
        if text then
          return { status = "success", output = text }
        end
      end
    end,

    tools = {
      ---Normalize raw tool calls from chat_output into the internal format
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table
      ---@return table
      format_tool_calls = function(self, tools)
        local formatted = {}
        for _, tool in ipairs(tools) do
          table.insert(formatted, {
            _index = tool._index,
            id = tool.id or string.format("call_%s_%d", os.time(), tool._index),
            thought_signature = tool.thought_signature,
            type = "function",
            ["function"] = {
              arguments = type(tool.args) == "table" and vim.json.encode(tool.args) or (tool.args or ""),
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
      output_response = function(self, tool_call, output)
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

    ---Function to run when the request has completed
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data? table
    ---@return nil
    on_exit = function(self, data)
      if data and data.status and data.status >= 400 then
        log:error("Error: %s", data.body)
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      type = "enum",
      desc = "The model that will complete your prompt. See https://ai.google.dev/gemini-api/docs/models/gemini for details.",
      default = "gemini-3.1-pro-preview",
      choices = {
        -- Gemini 3
        ["gemini-3.1-pro-preview"] = {
          formatted_name = "Gemini 3.1 Pro",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, has_vision = true },
        },
        ["gemini-3.1-flash-lite-preview"] = {
          formatted_name = "Gemini 3.1 Flash Lite",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, has_vision = true },
        },
        ["gemini-3-flash-preview"] = {
          formatted_name = "Gemini 3 Flash",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, has_vision = true },
        },

        -- Gemini 2.5
        ["gemini-2.5-pro"] = {
          formatted_name = "Gemini 2.5 Pro",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, has_vision = true },
        },
        ["gemini-2.5-flash"] = {
          formatted_name = "Gemini 2.5 Flash",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, has_vision = true },
        },
        ["gemini-2.5-flash-lite"] = {
          formatted_name = "Gemini 2.5 Flash Lite",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, has_vision = true },
        },

        -- Older models
        "gemini-2.0-flash",
        "gemini-1.5-flash",
        "gemini-1.5-pro",
      },
    },
    maxOutputTokens = {
      order = 2,
      mapping = "body.generationConfig",
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
      mapping = "body.generationConfig",
      type = "number",
      optional = true,
      default = nil,
      desc = "Controls the randomness of the output.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    topP = {
      order = 4,
      mapping = "body.generationConfig",
      type = "number",
      optional = true,
      default = nil,
      desc = "The maximum cumulative probability of tokens to consider when sampling.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    topK = {
      order = 5,
      mapping = "body.generationConfig",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to consider when sampling.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    thinkingLevel = {
      order = 6,
      mapping = "body.generationConfig.thinkingConfig",
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
    presencePenalty = {
      order = 7,
      mapping = "body.generationConfig",
      type = "number",
      optional = true,
      default = nil,
      desc = "Presence penalty applied to the next token's logprobs if the token has already been seen in the response.",
    },
    frequencyPenalty = {
      order = 8,
      mapping = "body.generationConfig",
      type = "number",
      optional = true,
      default = nil,
      desc = "Frequency penalty applied to the next token's logprobs, multiplied by the number of times each token has been seen in the response so far.",
    },
  },
}
