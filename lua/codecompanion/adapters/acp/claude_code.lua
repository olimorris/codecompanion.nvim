local helpers = require("codecompanion.adapters.acp.helpers")

---@class CodeCompanion.ACPAdapter.GeminiCLI: CodeCompanion.ACPAdapter
return {
  name = "claude_code",
  formatted_name = "Claude Code",
  type = "acp",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    vision = true,
  },
  commands = {
    default = {
      "npx",
      "--silent",
      "--yes",
      "@zed-industries/claude-code-acp",
    },
  },
  defaults = {
    auth_method = "claude-login", -- "anthropic-api-key"|"claude-login"
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  env = {
    ANTHROPIC_API_KEY = "ANTHROPIC_API_KEY",
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
      return helpers.form_messages(self, messages)
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.ACPAdapter
    ---@param code number
    ---@return nil
    on_exit = function(self, code) end,
  },
}
