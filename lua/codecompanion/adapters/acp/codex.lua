local helpers = require("codecompanion.adapters.acp.helpers")

local AUTH_ENV_BY_METHOD = {
  ["openai-api-key"] = {
    OPENAI_API_KEY = true,
  },
  ["codex-api-key"] = {
    CODEX_API_KEY = true,
  },
}

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
    auth_method = "openai-api-key", -- "openai-api-key"|"codex-api-key"|"chatgpt"
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  env = {
    OPENAI_API_KEY = "OPENAI_API_KEY",
    CODEX_API_KEY = "CODEX_API_KEY",
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
      local allowed_env = AUTH_ENV_BY_METHOD[self.defaults.auth_method] or {}
      local filtered_env = {}

      for env_name, env_value in pairs(self.env_replaced or {}) do
        if allowed_env[env_name] then
          filtered_env[env_name] = env_value
        end
      end

      self.env_replaced = filtered_env
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
