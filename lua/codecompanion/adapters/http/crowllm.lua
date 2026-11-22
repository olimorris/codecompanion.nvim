local adapter_utils = require("codecompanion.adapters.utils")
local deepseek = require("codecompanion.adapters.http.deepseek")
local tags = require("codecompanion.interactions.shared.tags")

---@class CodeCompanion.HTTPAdapter.CrowLLM: CodeCompanion.HTTPAdapter
return {
  name = "crowllm",
  formatted_name = "CrowLLM",
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
  url = "https://crowllm.com/v1/chat/completions",
  env = {
    api_key = "CROWLLM_API_KEY",
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
        deepseek.handlers.lifecycle.setup(self)

        local model_choice = adapter_utils.model_choice(self, { async = false })
        self.opts.vision = (model_choice and model_choice.opts and model_choice.opts.has_vision) == true

        return true
      end,

      on_exit = deepseek.handlers.lifecycle.on_exit,
    },

    request = {
      build_parameters = deepseek.handlers.request.build_parameters,

      ---@param self CodeCompanion.HTTPAdapter
      ---@param args { messages: table }
      ---@return table
      build_messages = function(self, args)
        return deepseek.build_messages(self, args.messages, function(msg)
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

      build_tools = deepseek.handlers.request.build_tools,
      build_reasoning = deepseek.handlers.request.build_reasoning,
    },

    response = {
      parse_chat = deepseek.handlers.response.parse_chat,
      parse_meta = deepseek.handlers.response.parse_meta,
      parse_tokens = deepseek.handlers.response.parse_tokens,
    },

    tools = {
      format_calls = deepseek.handlers.tools.format_calls,
      format_response = deepseek.handlers.tools.format_response,
    },
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. The gateway serves models from several labs behind one key.",
      ---@type string|fun(): string
      default = "glm-5.3",
      choices = {
        ["deepseek-v4-flash"] = {
          formatted_name = "DeepSeek V4 Flash",
          meta = { context_window = 128000 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["glm-5.3"] = {
          formatted_name = "GLM 5.3",
          meta = { context_window = 200000 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["kimi-k3"] = {
          formatted_name = "Kimi K3",
          meta = { context_window = 256000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["claude-opus-4-7"] = {
          formatted_name = "Claude Opus 4.7",
          meta = { context_window = 200000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["gemini-3.7-flash"] = {
          formatted_name = "Gemini 3.7 Flash",
          meta = { context_window = 1000000 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["grok-4.7:free"] = {
          formatted_name = "Grok 4.7 (free)",
          meta = { context_window = 256000 },
          opts = { can_reason = true, can_use_tools = true },
        },
      },
    },
  },
}
