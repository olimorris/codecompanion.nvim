local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.http.openai")

---@class CodeCompanion.HTTPAdapter.Mistral: CodeCompanion.HTTPAdapter
return {
  name = "mistral",
  formatted_name = "Mistral",
  roles = {
    llm = "assistant",
    user = "user",
    tool = "tool",
  },
  opts = {
    stream = true,
    vision = true,
    tools = true,
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "${url}/v1/chat/completions",
  env = {
    url = "https://api.mistral.ai",
    api_key = "MISTRAL_API_KEY",
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

      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
        if not model_opts.opts.has_vision then
          self.opts.vision = false
        end
        if model_opts.opts.has_function_calling ~= nil and not model_opts.opts.has_function_calling then
          self.opts.tools = false
        end
      end

      return true
    end,

    --- Use the OpenAI adapter for the bulk of the work
    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    form_tools = function(self, params)
      return openai.handlers.form_tools(self, params)
    end,
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      local pending_messages = self.pending_messages or {}
      local is_previous_tool = false
      for k, msg in ipairs(messages) do
        local is_tool = msg.role == "tool"
        local is_user = msg.role == "user"
        -- Mistral does not like user after tool messages, those should always be assistant
        if is_previous_tool and is_user then
          table.insert(pending_messages, msg)
          messages[k] = nil
          -- message was dropped, so for the next message, the previous one
          -- is still a tool
          is_tool = true
        else
          if not is_previous_tool then
            -- Flush pending messages whenever we can
            for i, m in ipairs(pending_messages) do
              table.insert(messages, m)
            end
            pending_messages = {}
          end
        end
        is_previous_tool = is_tool
      end

      -- Keep the pending messages for next round
      self.pending_messages = pending_messages

      return openai.handlers.form_messages(self, messages)
    end,
    chat_output = function(self, data, tools)
      if not data or data == "" then
        return nil
      end

      -- Handle both streamed data and structured response
      local data_mod = type(data) == "table" and data.body or adapter_utils.clean_streamed_data(data)
      local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

      if not ok or not json.choices or #json.choices == 0 then
        return nil
      end

      -- Process tool calls from all choices
      if self.opts.tools and tools then
        for _, choice in ipairs(json.choices) do
          local delta = self.opts.stream and choice.delta or choice.message

          if delta and delta.tool_calls and #delta.tool_calls > 0 then
            for i, tool in ipairs(delta.tool_calls) do
              local id = tool.id
              if not id or id == "" then
                id = string.format("call_%s_%s", json.created, i)
              end

              if self.opts.stream then
                local found = false
                for _, existing_tool in ipairs(tools) do
                  if existing_tool.id == id then
                    -- Append to arguments if this is a continuation of a stream
                    if tool["function"] and tool["function"]["arguments"] then
                      existing_tool["function"]["arguments"] = (existing_tool["function"]["arguments"] or "")
                        .. tool["function"]["arguments"]
                    end
                    found = true
                    break
                  end
                end

                if not found then
                  table.insert(tools, {
                    id = id,
                    type = tool.type,
                    ["function"] = {
                      name = tool["function"]["name"],
                      arguments = tool["function"]["arguments"] or "",
                    },
                  })
                end
              else
                table.insert(tools, {
                  id = id,
                  type = tool.type,
                  ["function"] = {
                    name = tool["function"]["name"],
                    arguments = tool["function"]["arguments"],
                  },
                })
              end
            end
          end
        end
      end

      -- Process message content from the first choice
      local choice = json.choices[1]
      local delta = self.opts.stream and choice.delta or choice.message

      if not delta then
        return nil
      end

      local output = {
        role = delta.role,
      }

      if delta.content then
        local content = delta.content
        if type(content) == "string" then
          output.content = content
        else
          output.reasoning = output.reasoning or {}
          output.reasoning.content = ""
          for _, c in ipairs(content) do
            if c.type == "thinking" then
              for _, thinking in ipairs(c.thinking) do
                output.reasoning.content = output.reasoning.content .. thinking.text
              end
            end
          end
        end
      else
        output.content = ""
      end

      return {
        status = "success",
        output = output,
      }
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
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "mistral-small-latest",
      choices = {
        -- Premier models
        "mistral-large-latest",
        ["pixtral-large-latest"] = { opts = { has_vision = true } },
        ["magistral-medium-latest"] = { opts = { can_reason = true } },
        ["magistral-small-latest"] = { opts = { can_reason = true } },
        ["mistral-medium-latest"] = { opts = { has_vision = true } },
        ["mistral-saba-latest"] = { opts = { has_function_calling = false } },
        "codestral-latest",
        "ministral-8b-latest",
        "ministral-3b-latest",
        -- Free models, latest
        ["mistral-small-latest"] = { opts = { has_vision = true } },
        ["pixtral-12b-2409"] = { opts = { has_vision = true } },
        -- Free models, research
        "open-mistral-nemo",
        "open-codestral-mamba",
      },
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "What sampling temperature to use, we recommend between 0.0 and 0.7. Higher values like 0.7 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 1.5, "Must be between 0 and 1.5"
      end,
    },
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "Nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    max_tokens = {
      order = 4,
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
      order = 5,
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
    random_seed = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "The seed to use for random sampling. If set, different calls will generate deterministic results.",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    presence_penalty = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Determines how much the model penalizes the repetition of words or phrases. A higher presence penalty encourages the model to use a wider variety of words and phrases, making the output more diverse and creative.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    frequency_penalty = {
      order = 8,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Penalizes the repetition of words based on their frequency in the generated text. A higher frequency penalty discourages the model from repeating words that have already appeared frequently in the output, promoting diversity and reducing repetition.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    n = {
      order = 9,
      mapping = "parameters",
      type = "number",
      default = 1,
      desc = "Number of completions to return for each request, input tokens are only billed once.",
    },
    safe_prompt = {
      order = 10,
      mapping = "parameters",
      type = "boolean",
      optional = true,
      default = false,
      desc = "Whether to inject a safety prompt before all conversations.",
    },
  },
}
