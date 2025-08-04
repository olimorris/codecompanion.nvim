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

      local session_update = data.sessionUpdate
      local content = data.content

      -- Only process agent message chunks for streaming
      if session_update ~= "agentMessageChunk" or not content or not content.text then
        return nil
      end

      log:debug("Processing chat output: %s", content.text)

      return {
        status = "success",
        output = {
          content = content.text,
        },
      }
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.ACPAdapter
    ---@param data? table
    ---@return nil
    on_exit = function(self, data)
      log:debug("Gemini CLI adapter exiting")
    end,
  },
}
