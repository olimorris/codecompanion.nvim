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
    "node",
    "/Users/Oli/Code/Neovim/gemini-cli/packages/cli",
    "--experimental-acp",
  },
  defaults = {
    auth_method = "gemini-api-key",
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  env = {
    GEMINI_API_KEY = "cmd:op read op://personal/Gemini_API/credential --no-newline",
  },
  parameters = {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
    },
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

    ---@param self CodeCompanion.ACPAdapter
    ---@param messages table
    ---@return table
    form_messages = function(self, messages)
      return vim
        .iter(messages)
        :filter(function(msg)
          return msg.role == self.roles.user
        end)
        :map(function(msg)
          return { type = "text", text = msg.content }
        end)
        :totable()
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
    ---@param code number
    ---@return nil
    on_exit = function(self, code)
      log:debug("Gemini CLI adapter exiting")
    end,
  },
}
