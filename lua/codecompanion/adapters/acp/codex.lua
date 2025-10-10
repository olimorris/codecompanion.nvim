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
    -- Claude Code has an annoying habit of outputting the entire contents of a
    -- file in a tool call. This messes up the chat buffer formatting.
    trim_tool_output = true,
  },
  commands = {
    default = {
      "codex-acp",
    },
  },
  defaults = {
    auth_method = "openai-api-key", -- "openai-api-key"|"codex-api-key"|"chatgpt"
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  env = {
    OPENAI_API_KEY = "OPENAI_API_KEY",
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
    ---@param capabilities table
    ---@return table
    form_messages = function(self, messages, capabilities)
      return helpers.form_messages(self, messages, capabilities)
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.ACPAdapter
    ---@param code number
    ---@return nil
    on_exit = function(self, code) end,
  },
}
