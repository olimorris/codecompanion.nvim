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

    ---@param self CodeCompanion.ACPAdapter
    ---@param tool_call table
    ---@param output string
    ---@return table
    output_response = function(self, tool_call, output)
      return helpers.output_response(self, tool_call, output)
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
