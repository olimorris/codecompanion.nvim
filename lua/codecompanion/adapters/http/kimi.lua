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

        local model_choice = adapter_utils.model_choice(self)
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
