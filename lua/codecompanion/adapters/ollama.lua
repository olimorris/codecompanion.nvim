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

---@class CodeCompanion.AdapterArgs
return {
  name = "Ollama",
  features = {
    text = true,
    vision = false,
  },
  url = "http://localhost:11434/api/chat",
  chat_prompt = [[
You are an AI programming assistant. When asked for your name, you must respond with "CodeCompanion". You were built by Oli Morris. Follow the user's requirements carefully & to the letter. Your expertise is strictly limited to software development topics. Avoid content that violates copyrights. For questions not related to software development, simply give a reminder that you are an AI programming assistant. Keep your answers short and impersonal.

You can answer general programming questions and perform the following tasks:
- Ask a question about the files in your current workspace
- Explain how the selected code works
- Generate unit tests for the selected code
- Propose a fix for the problems in the selected code
- Scaffold code for a new feature
- Ask questions about Neovim
- Ask how to do something in the terminal

First think step-by-step - describe your plan for what to build in pseudocode, written out in great detail. Then output the code in a single code block. Minimize any other prose. Use Markdown formatting in your answers. Make sure to include the programming language name at the start of the Markdown code blocks. Avoid wrapping the whole response in triple backticks. The user works in a text editor called Neovim which has a concept for editors with open files, integrated unit test support, an output pane that shows the output of running the code as well as an integrated terminal. The active document is the source code the user is looking at right now. You can only give one reply for each conversation turn.
  ]],
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
