---@class CodeCompanion.Adapter
---@field name string
---@field url string
---@field raw? table
---@field headers table
---@field parameters table
---@field callbacks table
---@field schema table
return {
  name = "Ollama",
  url = "http://localhost:11434/api/chat",
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
      return false
    end,

    ---Format any data before it's consumed by the other callbacks
    ---@param data table
    ---@return table
    format_data = function(data)
      return data
    end,

    ---Does the data contain an error?
    ---@param data string
    ---@return boolean
    has_error = function(data)
      return false
    end,

    ---Has the streaming completed?
    ---@param data table The data from the format_data callback
    ---@return boolean
    is_complete = function(data)
      data = vim.fn.json_decode(data)
      return data.done
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param json_data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@param messages table A table of all of the messages in the chat buffer
    ---@param current_message table The current/latest message in the chat buffer
    ---@return table
    output_chat = function(json_data, messages, current_message)
      local delta = json_data.message

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
    ---@param json_data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@param context table Useful context about the buffer to inline to
    ---@return table
    output_inline = function(json_data, context)
      return json_data.message.content
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
    temperature = {
      order = 2,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 0.8,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
  },
}
