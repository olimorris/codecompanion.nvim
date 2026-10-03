local helpers = require("codecompanion.adapters.acp.helpers")

---@class CodeCompanion.ACPAdapter.Kiro: CodeCompanion.ACPAdapter
return {
  name = "kiro",
  formatted_name = "Kiro",
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
      "kiro-cli",
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

      ---Manually handle authentication
      ---@param self CodeCompanion.ACPAdapter
      ---@return boolean
      auth = function(self)
        -- kiro-cli handles authentication exclusively through its kiro-cli CLI interface
        -- Users are expected to login there and then can use the ACP after. auth is therefore
        -- declared a success here to work around attempted authentication.
        return true
      end,
    },

    request = {
      build_messages = helpers.build_messages,
    },
  },
}
