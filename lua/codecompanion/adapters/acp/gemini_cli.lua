local log = require("codecompanion.utils.log")

---@class CodeCompanion.ACPAdapter.GeminiCLI: CodeCompanion.ACPAdapter
return {
  name = "gemini_cli",
  formatted_name = "Gemini CLI",
  type = "acp",
  roles = {
    llm = "assistant",
    user = "user",
  },
  command = {
    "gemini",
    "--experimental-acp",
  },
  defaults = {
    timeout = 30000,
  },
  env = {
    GEMINI_API_KEY = "YOUR-GEMINI-API-KEY-HERE",
  },
  parameters = {
    protocolVersion = "2024-11-05",
    capabilities = {},
    clientInfo = {
      name = "CodeCompanion",
      version = "1.0.0",
    },
  },
  handlers = {
    ---@param self CodeCompanion.ACPAdapter
    ---@return boolean
    setup = function(self)
      return true
    end,

    ---Determine if the stream data is complete.
    ---@param self CodeCompanion.ACPAdapter
    ---@param data table
    ---@return table|nil [status: string, output: table]
    chat_output = function(self, data)
      if type(data) ~= "table" then
        return nil
      end

      local output = {}

      if data.method == "streamAssistantMessageChunk" and data.params and data.params.chunk then
        local chunk = data.params.chunk
        local content = chunk.text or chunk.thought
        if content then
          output.content = content
        end
      end

      return {
        status = "status",
        output = output,
      }
    end,

    ---Determine if the stream data is complete.
    ---@param self CodeCompanion.ACPAdapter
    ---@param data table
    ---@return boolean
    is_done = function(self, data)
      return
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.ACPAdapter
    ---@param data? table
    ---@return nil
    on_exit = function(self, data)
      return
    end,
  },
  protocol = {
    ---Authenticate with the ACP service.
    ---@param self CodeCompanion.ACPAdapter
    ---@return nil
    authenticate = function(self)
      return
    end,

    ---Start a new ACP session with the adapter
    ---@param self CodeCompanion.ACPAdapter
    ---@return nil
    new_session = function(self)
      return
    end,

    ---Load a previously saved ACP session
    ---@param self CodeCompanion.ACPAdapter
    ---@return nil
    load_session = function(self)
      return
    end,

    ---Prompt the ACP adapter with messages
    ---@param self CodeCompanion.ACPAdapter
    ---@param messages table
    ---@return table
    prompt = function(self, messages)
      return messages
    end,
  },
}
