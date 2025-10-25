local adapter_utils = require("codecompanion.utils.adapters")
local openai = require("codecompanion.adapters.http.openai")

---@param message string
---@return string
local function strip_thinking_tags(message)
  local result = message:gsub("^<thought>", ""):gsub("^</thought>", "")
  return result
end

---@class CodeCompanion.HTTPAdapter.Gemini : CodeCompanion.HTTPAdapter
return {
  name = "gemini",
  formatted_name = "Gemini",
  roles = {
    llm = "assistant",
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
  url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
  env = {
    api_key = "GEMINI_API_KEY",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
  },
  handlers = {
    setup = function(self)
      -- Make sure the individual model options are set
      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
        if not model_opts.opts.has_vision then
          self.opts.vision = false
        end
      end

      if self.opts and self.opts.stream then
        self.parameters = self.parameters or {}
        self.parameters.stream = true
        self.parameters.stream_options = { include_usage = true }
      end

      return true
    end,

    --- Use the OpenAI adapter for the bulk of the work
    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    form_parameters = function(self, params, messages)
      local processed_params = openai.handlers.form_parameters(self, params, messages)
      -- https://ai.google.dev/gemini-api/docs/openai#thinking
      processed_params.extra_body =
        vim.tbl_deep_extend("force", processed_params.extra_body or {}, { google = { thinking_config = {} } })
      local thinking_config = processed_params.extra_body.google.thinking_config
      thinking_config.include_thoughts = thinking_config.thinkingBudget ~= 0

      return processed_params
    end,
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
    end,
    form_messages = function(self, messages)
      -- WARN: System prompts must be merged as per #2522
      messages = adapter_utils.merge_system_messages(messages)

      local result = openai.handlers.form_messages(self, messages)

      local STANDARD_TOOL_CALL_FIELDS = {
        "id",
        "type",
        "function",
        "_index",
      }

      -- Post-process to preserve extra fields (like thought signatures)
      -- Ref: https://ai.google.dev/gemini-api/docs/thought-signatures#openai
      for _, msg in ipairs(result.messages) do
        local original_msg = nil
        for _, orig in ipairs(messages) do
          if orig.role == msg.role and orig.tools and orig.tools.calls then
            original_msg = orig
            break
          end
        end

        -- If we have tool_calls in the original message then preserve non-standard fields
        if msg.tool_calls and original_msg and original_msg.tools and original_msg.tools.calls then
          for i, tool_call in ipairs(msg.tool_calls) do
            local original_tool = original_msg.tools.calls[i]
            if original_tool then
              for key, value in pairs(original_tool) do
                if not vim.tbl_contains(STANDARD_TOOL_CALL_FIELDS, key) then
                  tool_call[key] = value
                end
              end
            end
          end
        end
      end

      return result
    end,
    chat_output = function(self, data, tools)
      local openai_output = openai.handlers.chat_output(self, data, tools)
      if openai_output == nil then
        return
      end

      local extra_content = openai_output.extra_content
      if extra_content then
        local reasoning = strip_thinking_tags(openai_output.output.content)
        openai_output.output.reasoning = { content = reasoning }
        openai_output.output.content = nil
        openai_output.extra_content = nil -- maybe not needed?
      elseif openai_output.output.content then
        openai_output.output.content = strip_thinking_tags(openai_output.output.content)
      end

      return openai_output
    end,

    ---@param self CodeCompanion.HTTPAdapter.Gemini
    ---@param data table The reasoning output from the LLM
    ---@return nil|{ content: string, _data: table }
    form_reasoning = function(self, data)
      if data == nil or not vim.iter(data):any(function(item)
        return item ~= nil
      end) then
        return
      end

      local content = vim
        .iter(data)
        :map(function(item)
          local val = item.content or item
          if type(val) == "string" then
            return val
          end
        end)
        :filter(function(content)
          return content ~= nil
        end)
        :join("")

      return {
        content = content,
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
      desc = "The model that will complete your prompt. See https://ai.google.dev/gemini-api/docs/models/gemini#model-variations for additional details and options.",
      default = "gemini-3-pro-preview",
      choices = {
        ["gemini-3-pro-preview"] = { formatted_name = "Gemini 3 Pro", opts = { can_reason = true, has_vision = true } },
        ["gemini-3-flash-preview"] = {
          formatted_name = "Gemini 3 Flash",
          opts = { can_reason = true, has_vision = true },
        },
        ["gemini-2.5-pro"] = {
          formatted_name = "Gemini 2.5 Pro",
          opts = { can_reason = true, has_vision = true },
          thinkingBudget = { low = 128, high = 32768 },
        },
        ["gemini-2.5-flash"] = {
          formatted_name = "Gemini 2.5 Flash",
          opts = { can_reason = true, has_vision = true },
          thinkingBudget = { low = 0, high = 24576 },
        },
        ["gemini-2.5-flash-preview-05-20"] = {
          formatted_name = "Gemini 2.5 Flash Preview",
          opts = { can_reason = true, has_vision = true },
          thinkingBudget = { low = 0, high = 24576 },
        },
        ["gemini-2.0-flash"] = { formatted_name = "Gemini 2.0 Flash", opts = { has_vision = true } },
        ["gemini-2.0-flash-lite"] = { formatted_name = "Gemini 2.0 Flash Lite", opts = { has_vision = true } },
        ["gemini-1.5-pro"] = { formatted_name = "Gemini 1.5 Pro", opts = { has_vision = true } },
        ["gemini-1.5-flash"] = { formatted_name = "Gemini 1.5 Flash", opts = { has_vision = true } },
      },
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 2,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to include in a response candidate. Note: The default value varies by model",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = nil,
      desc = "Controls the randomness of the output.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum cumulative probability of tokens to consider when sampling. The model uses combined Top-k and Top-p (nucleus) sampling. Tokens are sorted based on their assigned probabilities so that only the most likely tokens are considered. Top-k sampling directly limits the maximum number of tokens to consider, while Nucleus sampling limits the number of tokens based on the cumulative probability.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    thinkingBudget = {
      -- https://ai.google.dev/gemini-api/docs/thinking#set-budget
      order = 5,
      mapping = "parameters.extra_body.google.thinking_config",
      type = "integer",
      optional = true,
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      enabled = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        if self.schema.model.choices[model] and self.schema.model.choices[model].opts then
          return self.schema.model.choices[model].opts.can_reason
        end
        return false
      end,
      default = -1, -- dynamic reasoning
      -- TODO: validate requires having `self` in the params.
      desc = "The thinkingBudget parameter guides the model on the number of thinking tokens to use when generating a response.",
    },
  },
}
