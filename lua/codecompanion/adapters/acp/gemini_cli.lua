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
  },
  defaults = {
    auth_method = "gemini-api-key",
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  env = {
    GEMINI_API_KEY = "GEMINI_API_KEY",
  },
  parameters = {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
    },
    clientInfo = {
      name = "CodeCompanion.nvim",
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
          -- Ensure we're only sending user messages that Gemini hasn't seen before
          return msg.role == self.roles.user and not msg._meta.sent
        end)
        :map(function(msg)
          return { type = "text", text = msg.content }
        end)
        :totable()
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
