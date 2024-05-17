local log = require("codecompanion.utils.log")

local function get_ollama_choices()
  local handle = io.popen("ollama list")
  local result = {}

  if handle then
    for line in handle:lines() do
      local first_word = line:match("%S+")
      if first_word ~= nil and first_word ~= "NAME" then
        table.insert(result, first_word)
      end
    end

    handle:close()
  end
  return result
end

---@class CodeCompanion.Adapter
---@field name string
---@field features table
---@field url string
---@field raw? table
---@field headers table
---@field parameters table
---@field callbacks table
---@field callbacks.form_parameters fun()
---@field callbacks.form_messages fun()
---@field callbacks.is_complete fun()
---@field callbacks.chat_output fun()
---@field callbacks.inline_output fun()
---@field schema table
return {
  name = "Ollama",
  features = {
    text = true,
    vision = false,
  },
  url = "http://localhost:11434/api/chat",
  callbacks = {
    ---Set the parameters
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(params, messages)
      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(messages)
      return { messages = messages }
    end,

    ---Has the streaming completed?
    ---@param data table The data from the format_data callback
    ---@return boolean
    is_complete = function(data)
      if data then
        data = vim.fn.json_decode(data)
        return data.done
      end
      return false
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@return table|nil
    chat_output = function(data)
      local output = {}

      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          return {
            status = "error",
            output = string.format("Error malformed json: %s", json),
          }
        end

        local message = json.message

        if message.content then
          output.content = message.content
          output.role = message.role or nil
        end

        -- log:trace("----- For Adapter test creation -----\nOutput: %s\n ---------- // END ----------", output)

        return {
          status = "success",
          output = output,
        }
      end

      return nil
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@param context table Useful context about the buffer to inline to
    ---@return table|nil
    inline_output = function(data, context)
      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          log:error("Error malformed json: %s", json)
          return
        end

        return json.message.content
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use.",
      default = "deepseek-coder:6.7b",
      choices = get_ollama_choices(),
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
