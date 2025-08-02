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
---@param adapter string|table|function
---@return table|
function M.get_adapter_from_config(adapter)
  if type(adapter) == "function" then
    return adapter()
  end

  if type(adapter) == "string" then
    local ns, name = adapter:match("^(%w+)%.(.+)$")
    if ns and name then
      if ns == "acp" and config.adapters.acp and config.adapters.acp[name] then
        return config.adapters.acp[name]
      end
      if ns == "http" and config.adapters.http and config.adapters.http[name] then
        return config.adapters.http[name]
      end
    end
    if config.adapters.acp and config.adapters.acp[adapter] then
      return config.adapters.acp[adapter]
    end
    if config.adapters.http and config.adapters.http[adapter] then
      return config.adapters.http[adapter]
    end

    -- TODO: Remove in v18.0.0
    if config.adapters[adapter] then
      return config.adapters[adapter]
    end
  end

  return adapter
end

return M
