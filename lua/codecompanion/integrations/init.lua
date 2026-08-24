local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

local INTEGRATIONS = {
  "herdr",
}

---Call a function for every integration that's enabled in the user's config
---@param callback fun(integration: table)
---@return nil
local function enabled_integrations(callback)
  for _, name in ipairs(INTEGRATIONS) do
    local integration_config = config.integrations[name]
    if integration_config and integration_config.enabled then
      local ok, integration = pcall(require, "codecompanion.integrations." .. name)
      if not ok then
        log:warn("Failed to load integration `%s`: %s", name, integration)
      else
        callback(integration)
      end
    end
  end
end

---@return nil
function M.setup()
  enabled_integrations(function(integration)
    integration.setup()
  end)
end

---Environment overrides for ACP adapters
---@return table<string, string>
function M.acp_env()
  local env = {}
  enabled_integrations(function(integration)
    if integration.acp_env then
      env = vim.tbl_extend("force", env, integration.acp_env())
    end
  end)
  return env
end

return M
