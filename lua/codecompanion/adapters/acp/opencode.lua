local helpers = require("codecompanion.adapters.acp.helpers")

---@class CodeCompanion.ACPAdapter.OpenCode: CodeCompanion.ACPAdapter
return {
  name = "opencode",
  formatted_name = "OpenCode",
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
      "opencode",
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
        -- opencode emits "opencode-login" as an authMethod which seems to be an
        -- invalid command. So work around this by declaring auth a success
        return true
      end,
    },

    request = {
      build_messages = helpers.build_messages,
    },
  },
}
