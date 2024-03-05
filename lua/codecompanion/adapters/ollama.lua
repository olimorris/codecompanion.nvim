local Adapter = require("codecompanion.adapter")

---@class CodeCompanion.Adapter
---@field name string
---@field url string
---@field raw? table
---@field headers table
---@field parameters table
---@field schema table

local adapter = {
  name = "Ollama",
  url = "http://localhost:11434/api/chat",
  raw = {
    "--no-buffer",
  },
  callbacks = {
    ---Set the format of the role and content for the messages from the chat buffer
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(messages)
      return { messages = messages }
    end,

    ---Format any data before it's consumed by the other callbacks
    ---@param data table
    ---@return table
    format_data = function(data)
      return data
    end,

    ---Has the streaming completed?
    ---@param data table The data from the format_data callback
    ---@return boolean
    is_complete = function(data)
      return data.done == true
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param data table The streamed data from the API, also formatted by the format_data callback
    ---@param messages table A table of all of the messages in the chat buffer
    ---@param current_message table The current/latest message in the chat buffer
    ---@return table
    output_chat = function(data, messages, current_message)
      local delta = data.message

      if delta.role and delta.role ~= current_message.role then
        current_message = { role = delta.role, content = "" }
        table.insert(messages, current_message)
      end

      if delta.content then
        current_message.content = current_message.content .. delta.content
      end

      return current_message
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param data table The streamed data from the API, also formatted by the format_data callback
    ---@param context table Useful context about the buffer to inline to
    ---@return table
    output_inline = function(data, context)
      return data.message.content
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use.",
      default = "llama2",
      choices = {
        "llama2",
        "mistral",
        "dolphin-phi",
        "phi",
      },
    },
  },
}

return Adapter.new(adapter)
