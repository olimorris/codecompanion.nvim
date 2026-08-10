local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

local INTEGRATIONS = {
  "herdr",
}

---Set up any third-party integrations that are enabled in the user's config
---@return nil
function M.setup()
  for _, name in ipairs(INTEGRATIONS) do
    local integration_config = config.integrations[name]
    if integration_config and integration_config.enabled then
      local ok, integration = pcall(require, "codecompanion.integrations." .. name)
      if not ok then
        log:warn("Failed to load integration `%s`: %s", name, integration)
      else
        integration.setup()
      end
    end
  end
end

return M
