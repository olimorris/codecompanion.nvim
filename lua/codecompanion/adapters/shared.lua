local config = require("codecompanion.config")
local utils = require("codecompanion.utils.adapters")

local M = {}

---Replace roles in the messages with the adapter's defined roles
---@param adapter table
---@param messages table
---@return table
function M.map_roles(adapter, messages)
  return utils.map_roles(adapter.roles, messages)
end

---Get adapter configuration from various sources
---@param adapter string
---@return table|nil
function M.get_adapter_from_config(adapter)
  if config.adapters.acp and config.adapters.acp[adapter] then
    return config.adapters.acp[adapter]
  end
  if config.adapters.http and config.adapters.http[adapter] then
    return config.adapters.http[adapter]
  end

  -- TODO: Remove in v19.0.0
  return config.adapters[adapter]
end

return M
