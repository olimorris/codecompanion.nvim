local adapter_utils = require("codecompanion.adapters.utils")
local deepseek = require("codecompanion.adapters.http.deepseek")
local tags = require("codecompanion.interactions.shared.tags")

---@class CodeCompanion.HTTPAdapter.DeepSeek: CodeCompanion.HTTPAdapter
return {
  name = "kimi",
  formatted_name = "Kimi",
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
  url = "https://api.moonshot.ai/v1/chat/completions",
  env = {
    api_key = "MOONSHOT_API_KEY",
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
      parse_inline = deepseek.handlers.response.parse_inline,
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
      desc = "ID of the model to use.",
      ---@type string|fun(): string
      default = "kimi-k2.7-code",
      choices = {
        ["kimi-k3"] = {
          formatted_name = "Kimi K3",
          meta = { context_window = 1048576 },
          opts = { can_reason = true, can_use_tools = true, has_vision = true },
        },
        ["kimi-k2.7-code"] = {
          formatted_name = "Kimi K2.7 Code",
          meta = { context_window = 262144 },
          opts = { can_reason = true, can_use_tools = true },
        },
        ["kimi-k2.7-code-highspeed"] = {
          formatted_name = "Kimi K2.7 Code HighSpeed",
          meta = { context_window = 262144 },
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
      default = "max",
      desc = "Constrains effort on reasoning for reasoning models. Only 'high' and 'max' are supported by DeepSeek V4.",
      enabled = function(self)
        local model = adapter_utils.model(self)
        if vim.tbl_contains({ "kimi-k3" }, model) then
          return true
        end
        return false
      end,
      choices = { "max" },
    },
    ---@type CodeCompanion.Schema
    ["thinking.type"] = {
      order = 3,
      mapping = "parameters",
      type = "enum",
      optional = true,
      default = "enabled",
      desc = "Whether to enable thinking mode. 'enabled' turns on reasoning, 'disabled' turns it off.",
      enabled = function(self)
        local model = adapter_utils.model(self)
        if vim.startswith(model, "kimi-k2.7") then
          return true
        end
        return false
      end,
      choices = { "enabled", "disabled" },
    },
  },
}
