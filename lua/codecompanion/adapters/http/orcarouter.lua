local adapter_utils = require("codecompanion.adapters.utils")
local deepseek = require("codecompanion.adapters.http.deepseek")
local tags = require("codecompanion.interactions.shared.tags")

---@class CodeCompanion.HTTPAdapter.OrcaRouter: CodeCompanion.HTTPAdapter
return {
  name = "orcarouter",
  formatted_name = "OrcaRouter",
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
  url = "https://api.orcarouter.ai/v1/chat/completions",
  env = {
    api_key = "ORCAROUTER_API_KEY",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
    ["HTTP-Referer"] = "https://github.com/olimorris/codecompanion.nvim",
    ["X-Title"] = "CodeCompanion",
  },
  handlers = {
    lifecycle = {
      ---@param self CodeCompanion.HTTPAdapter
      ---@return boolean
      setup = function(self)
        deepseek.handlers.lifecycle.setup(self)

        local model_choice = adapter_utils.model_choice(self, { async = false })
        self.opts.vision = (model_choice and model_choice.opts and model_choice.opts.has_vision) == true

        return true
      end,

      on_exit = function(self, data)
        return deepseek.handlers.lifecycle.on_exit(self, data)
      end,
    },

    request = {
      ---Set the parameters
      ---@param self CodeCompanion.HTTPAdapter
      ---@param params table
      ---@param messages table
      ---@return table
      build_parameters = function(self, params, messages)
        return deepseek.handlers.request.build_parameters(self, params, messages)
      end,

      ---@param self CodeCompanion.HTTPAdapter
      ---@param messages table
      ---@return table
      build_messages = function(self, messages)
        return deepseek.build_messages(self, messages, function(msg)
          if msg._meta and msg._meta.tag == tags.IMAGE and msg.context and msg.context.mimetype then
            if not (self.opts and self.opts.vision) then
              return nil
            end
            msg.content = {
              {
                type = "image_url",
                image_url = {
                  url = string.format("data:%s;base64,%s", msg.context.mimetype, msg.content),
                },
              },
            }
          end
          return msg
        end)
      end,

      ---Provides the schemas of the tools that are available to the LLM to call
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table<string, table>
      ---@return table|nil
      build_tools = function(self, tools)
        return deepseek.handlers.request.build_tools(self, tools)
      end,

      ---Aggregate reasoning parts into a string
      ---@param self CodeCompanion.HTTPAdapter
      ---@param parts table
      ---@return string
      build_reasoning = function(self, parts)
        return deepseek.handlers.request.build_reasoning(self, parts)
      end,
    },

    response = {
      ---Output the data from the API ready for insertion into the chat buffer
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
      ---@param tools? table The table to write any tool output to
      ---@return table|nil
      parse_chat = function(self, data, tools)
        return deepseek.handlers.response.parse_chat(self, data, tools)
      end,

      ---Extract reasoning_content from the response
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table
      ---@return table
      parse_meta = function(self, data)
        return deepseek.handlers.response.parse_meta(self, data)
      end,

      ---Output the data from the API for the inline assistant
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table
      ---@param context table?
      ---@return table|nil
      parse_inline = function(self, data, context)
        return deepseek.handlers.response.parse_inline(self, data, context)
      end,

      ---Returns the number of tokens generated from the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param data table
      ---@return number|nil
      parse_tokens = function(self, data)
        return deepseek.handlers.response.parse_tokens(self, data)
      end,
    },

    tools = {
      ---Format the tool calls for the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tools table
      ---@return table
      format_calls = function(self, tools)
        return deepseek.handlers.tools.format_calls(self, tools)
      end,

      ---Format the tool response for the LLM
      ---@param self CodeCompanion.HTTPAdapter
      ---@param tool_call table
      ---@param output string
      ---@return table
      format_response = function(self, tool_call, output)
        return deepseek.handlers.tools.format_response(self, tool_call, output)
      end,
    },
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See https://api.orcarouter.ai/v1/models for the full catalog.",
      ---@type string|fun(): string
      default = "openai/gpt-5.4-mini",
      choices = {
        ["openai/gpt-5.6-sol"] = {
          formatted_name = "GPT 5.6 Sol",
          meta = { context_window = 128000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["openai/gpt-5.5"] = {
          formatted_name = "GPT 5.5",
          meta = { context_window = 128000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["openai/gpt-5.4-mini"] = {
          formatted_name = "GPT 5.4 Mini",
          meta = { context_window = 128000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["anthropic/claude-sonnet-5"] = {
          formatted_name = "Claude Sonnet 5",
          meta = { context_window = 200000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["anthropic/claude-sonnet-4.6"] = {
          formatted_name = "Claude Sonnet 4.6",
          meta = { context_window = 200000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["anthropic/claude-opus-4.8"] = {
          formatted_name = "Claude Opus 4.8",
          meta = { context_window = 200000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["google/gemini-3.5-flash"] = {
          formatted_name = "Gemini 3.5 Flash",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["deepseek/deepseek-v4-pro"] = {
          formatted_name = "DeepSeek V4 Pro",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["deepseek/deepseek-v4-flash"] = {
          formatted_name = "DeepSeek V4 Flash",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["grok/grok-4.3"] = {
          formatted_name = "Grok 4.3",
          meta = { context_window = 128000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["qwen/qwen3.7-max"] = {
          formatted_name = "Qwen 3.7 Max",
          meta = { context_window = 128000 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["z-ai/glm-5.2"] = {
          formatted_name = "GLM 5.2",
          meta = { context_window = 128000 },
          opts = { can_reason = true, can_use_tools = true },
        },
      },
    },
    ---@type CodeCompanion.Schema
    reasoning_effort = {
      order = 2,
      mapping = "parameters",
      type = "string",
      optional = true,
      ---@param self CodeCompanion.HTTPAdapter
      ---@return boolean
      enabled = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model(self)
        end
        local choices = self.schema.model.choices
        if type(choices) == "function" then
          choices = choices(self)
        end
        return (choices and choices[model] and choices[model].opts and choices[model].opts.can_reason) == true
      end,
      default = "medium",
      desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.",
      choices = { "high", "medium", "low" },
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 4,
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
    stop = {
      order = 6,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Up to 4 sequences where the API will stop generating further tokens.",
      validate = function(l)
        return #l >= 1 and #l <= 4, "Must have between 1 and 4 elements"
      end,
    },
  },
}
