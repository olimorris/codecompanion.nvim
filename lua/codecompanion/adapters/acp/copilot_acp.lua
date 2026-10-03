local helpers = require("codecompanion.adapters.acp.helpers")

---@class CodeCompanion.ACPAdapter.Copilot: CodeCompanion.ACPAdapter
return {
  name = "copilot_acp",
  formatted_name = "Copilot",
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
      "copilot",
      "--acp",
      "--stdio",
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

      ---Manually handle authentication
      ---@param self CodeCompanion.ACPAdapter
      ---@return boolean
      auth = function(self)
        return true
      end,
    },

    request = {
      build_messages = helpers.build_messages,
    },
  },
}
