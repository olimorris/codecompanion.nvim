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
    if config.adapters.acp and config.adapters.acp[adapter] then
      return "acp"
    end
    if config.adapters.http and config.adapters.http[adapter] then
      return "http"
    end

    ---TODO: Remove in v18.0.0
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
  if adapter_type(adapter) == "acp" then
    return require("codecompanion.adapters.acp").resolve(adapter, opts)
  end
  return require("codecompanion.adapters.http").resolve(adapter, opts)
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
  if adapter_type(adapter) == "acp" then
    return require("codecompanion.adapters.acp").extend(adapter, opts)
  end
  return require("codecompanion.adapters.http").extend(adapter, opts)
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
