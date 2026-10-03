local helpers = require("codecompanion.adapters.acp.helpers")

---@class CodeCompanion.ACPAdapter.KiloCode: CodeCompanion.ACPAdapter
return {
  name = "kilocode",
  formatted_name = "Kilo Code",
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
      "kilo",
      "acp",
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

      ---@param self CodeCompanion.ACPAdapter
      ---@return boolean
      auth = function(self)
        -- Declaring auth a success
        return true
      end,
    },

    request = {
      build_messages = helpers.build_messages,
    },
  },
}
