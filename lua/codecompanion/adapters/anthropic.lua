local Adapter = require("codecompanion.adapter")

---@class CodeCompanion.Adapter
---@field name string
---@field url string
---@field raw? table
---@field headers table
---@field parameters table
---@field callbacks table
---@field schema table
local adapter = {
  name = "Anthropic",
  url = "https://api.anthropic.com/v1/messages",
  env = {
    anthropic_api_key = "ANTHROPIC_API_KEY",
  },
  headers = {
    ["anthropic-version"] = "2023-06-01",
    -- ["anthropic-beta"] = "messages-2023-12-15",
    ["content-type"] = "application/json",
    ["x-api-key"] = "${anthropic_api_key}",
  },
  parameters = {
    stream = true,
  },
  callbacks = {
    ---Set the format of the role and content for the messages from the chat buffer
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(messages)
      return { messages = messages }
    end,

    ---Does this streamed data need to be skipped?
    ---@param data table
    ---@return boolean
    should_skip = function(data)
      if type(data) == "string" then
        return string.sub(data, 1, 6) == "event:"
      end
      return false
    end,

    ---Format any data before it's consumed by the other callbacks
    ---@param data string
    ---@return string
    format_data = function(data)
      return data:sub(6)
    end,

    ---Does the data contain an error?
    ---@param data string
    ---@return boolean
    has_error = function(data)
      local msg = "event: error"
      return string.sub(data, 1, string.len(msg)) == msg
    end,

    ---Has the streaming completed?
    ---@param data string The data from the format_data callback
    ---@return boolean
    is_complete = function(data)
      local ok
      ok, data = pcall(vim.fn.json_decode, data)
      if ok and data.type then
        return data.type == "message_stop"
      end
      return false
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param json_data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@param messages table A table of all of the messages in the chat buffer
    ---@param current_message table The current/latest message in the chat buffer
    ---@return table
    output_chat = function(json_data, messages, current_message)
      if json_data.type == "message_start" then
        current_message = { role = json_data.message.role, content = "" }
        table.insert(messages, current_message)
      end

      if json_data.type == "content_block_delta" then
        current_message.content = current_message.content .. json_data.delta.text
      end

      return current_message
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param json_data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@param context table Useful context about the buffer to inline to
    ---@return table|nil
    output_inline = function(json_data, context)
      if json_data.type == "content_block_delta" then
        return json_data.delta.text
      end
      return nil
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "claude-3-opus-20240229",
      choices = {
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-2.1",
      },
    },
    max_tokens = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1024,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "What sampling temperature to use, between 0 and 1. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
  },
}

return Adapter.new(adapter)
