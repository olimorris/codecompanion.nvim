local helpers = require("codecompanion.adapters.acp.helpers")

---@class CodeCompanion.ACPAdapter.AuggieCLI: CodeCompanion.ACPAdapter
return {
  name = "auggie_cli",
  formatted_name = "Auggie CLI",
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
      "auggie",
      "--acp",
    },
  },
  defaults = {
    mcpServers = {},
    timeout = 20000, -- 20 seconds
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
