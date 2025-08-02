local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local shared = require("codecompanion.adapters.shared")

local M = {}

---Determine the adapter type
---@param adapter string|table
---@return string
local function adapter_type(adapter)
  if type(adapter) == "table" and adapter.type then
    return adapter.type
  end
  if type(adapter) == "string" then
    local ns, name = adapter:match("^(%w+)%.(.+)$")
    if ns and name then
      if ns == "acp" and config.adapters.acp and config.adapters.acp[name] then
        return "acp"
      end
      if ns == "http" and config.adapters.http and config.adapters.http[name] then
        return "http"
      end
    end
    if config.adapters.acp and config.adapters.acp[adapter] then
      return "acp"
    end
    if config.adapters.http and config.adapters.http[adapter] then
      return "http"
    end
    -- TODO: Remove in v18.0.0
    if config.adapters[adapter] then
      return "http"
    end
  end
  -- The fallback
  return "http"
end

---Factory method to resolve adapters
---@param adapter string|table
---@param opts? table
---@return CodeCompanion.ACPAdapter|CodeCompanion.HTTPAdapter
function M.resolve(adapter, opts)
  adapter = adapter or config.strategies.chat.adapter

  local adapter_type_val = adapter_type(adapter)
  local config_adapter = shared.get_adapter_from_config(adapter)
  if adapter_type_val == "acp" then
    return require("codecompanion.adapters.acp").resolve(config_adapter or adapter, opts)
  end
  return require("codecompanion.adapters.http").resolve(config_adapter or adapter, opts)
end

---Factory method to check if the adapter has been resolved
---@param adapter string|table
---@return boolean
function M.resolved(adapter)
  if not adapter then
    return false
  end

  if adapter_type(adapter) == "acp" then
    return require("codecompanion.adapters.acp").resolved(adapter)
  end
  return require("codecompanion.adapters.http").resolved(adapter)
end

---Factory method to extend the adapter
---@param adapter string|table
---@param opts? table
---@return CodeCompanion.ACPAdapter|CodeCompanion.HTTPAdapter
function M.extend(adapter, opts)
  local adapter_type_val = adapter_type(adapter)
  local config_adapter = shared.get_adapter_from_config(adapter)

  -- If config_adapter is a function, we need to handle it carefully to avoid recursion
  if type(config_adapter) == "function" and type(adapter) == "string" then
    local original_http_adapter = nil
    local original_root_adapter = nil

    if config.adapters.http and config.adapters.http[adapter] then
      original_http_adapter = config.adapters.http[adapter]
      config.adapters.http[adapter] = nil
    end
    -- TODO : Remove in v18.0.0
    if config.adapters[adapter] then
      original_root_adapter = config.adapters[adapter]
      config.adapters[adapter] = nil
    end

    local executed_adapter = config_adapter()

    -- Restore the original function
    if original_http_adapter then
      config.adapters.http[adapter] = original_http_adapter
    end

    -- TODO: Remove in v18.0.0
    if original_root_adapter then
      config.adapters[adapter] = original_root_adapter
    end

    if adapter_type_val == "acp" then
      return require("codecompanion.adapters.acp").extend(executed_adapter, opts)
    end
    return require("codecompanion.adapters.http").extend(executed_adapter, opts)
  end

  if adapter_type_val == "acp" then
    return require("codecompanion.adapters.acp").extend(config_adapter or adapter, opts)
  end
  return require("codecompanion.adapters.http").extend(config_adapter or adapter, opts)
end

---Factory method to make adapters safe for serialization
---@param adapter string|table
---@return table
function M.make_safe(adapter)
  if adapter_type(adapter) == "acp" then
    return require("codecompanion.adapters.acp").make_safe(adapter)
  end
  return require("codecompanion.adapters.http").make_safe(adapter)
end

---Backwards compatibility: expose HTTP methods directly at root level
---@param adapter CodeCompanion.HTTPAdapter
---@return CodeCompanion.HTTPAdapter
function M.set_model(adapter)
  return require("codecompanion.adapters.http").set_model(adapter)
end

return M
