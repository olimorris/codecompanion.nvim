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
---@param name string
---@param config_table table
---@return table|nil
function M.get_adapter_config(name, config_table)
  local ok, adapter_config

  -- Try requiring from adapters directory first
  ok, adapter_config = pcall(require, config_table.module_path .. name)
  if ok then
    return adapter_config
  end

  -- Try config.adapters structure
  adapter_config = config_table.config_source[name]
  if adapter_config then
    if type(adapter_config) == "function" then
      return adapter_config()
    end
    return adapter_config
  end

  return nil
end

return M
