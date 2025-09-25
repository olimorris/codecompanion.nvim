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
      "npx",
      "--silent",
      "--yes",
      "@zed-industries/claude-code-acp",
    },
  },
  defaults = {
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  env = {
    CLAUDE_CODE_OAUTH_TOKEN = "CLAUDE_CODE_OAUTH_TOKEN",
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

    ---Manually handle authentication
    ---@param self CodeCompanion.ACPAdapter
    ---@return boolean
    auth = function(self)
      local token = self.env_replaced.CLAUDE_CODE_OAUTH_TOKEN
      if token and token ~= "" then
        vim.env.CLAUDE_CODE_OAUTH_TOKEN = token
        return true
      end
      return false
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
