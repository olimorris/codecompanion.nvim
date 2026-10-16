local helpers = require("codecompanion.adapters.acp.helpers")

---@class CodeCompanion.ACPAdapter.Codex: CodeCompanion.ACPAdapter
return {
  name = "codex",
  formatted_name = "Codex",
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
      "codex-acp",
    },
  },
  defaults = {
    auth_method = "api-key", -- "api-key"|"chat-gpt"
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
    lifecycle = {
      ---@param self CodeCompanion.ACPAdapter
      ---@return boolean
      setup = function(self)
        return true
      end,
    },

    request = {
      build_messages = helpers.build_messages,
    },
  },
}
