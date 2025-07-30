local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

-- Auto-detect adapter type and route to appropriate implementation
local function get_adapter_type(adapter)
  if type(adapter) == "table" and adapter.type then
    return adapter.type
  end
  if type(adapter) == "string" then
    -- Check if it's in the ACP config section
    if config.adapters.acp and config.adapters.acp[adapter] then
      return "acp"
    end
    -- Check new http structure
    if config.adapters.http and config.adapters.http[adapter] then
      return "http"
    end
    -- Fallback: check root level (backwards compatibility)
    if config.adapters[adapter] then
      return "http" -- Default to http for backwards compatibility
    end
  end
  return "http" -- Default fallback
end

-- Factory method to resolve adapters
function M.resolve(adapter, opts)
  local adapter_type = get_adapter_type(adapter)

  if adapter_type == "acp" then
    return require("codecompanion.adapters.acp").resolve(adapter, opts)
  else
    return require("codecompanion.adapters.http").resolve(adapter, opts)
  end
end

-- Factory method to check if adapter is resolved
function M.resolved(adapter)
  if not adapter then
    return false
  end

  local adapter_type = get_adapter_type(adapter)

  if adapter_type == "acp" then
    return require("codecompanion.adapters.acp").resolved(adapter)
  else
    return require("codecompanion.adapters.http").resolved(adapter)
  end
end

-- Factory method to extend adapters
function M.extend(adapter, opts)
  local adapter_type = get_adapter_type(adapter)

  if adapter_type == "acp" then
    return require("codecompanion.adapters.acp").extend(adapter, opts)
  else
    return require("codecompanion.adapters.http").extend(adapter, opts)
  end
end

-- Factory method to make adapters safe for serialization
function M.make_safe(adapter)
  local adapter_type = get_adapter_type(adapter)

  if adapter_type == "acp" then
    return require("codecompanion.adapters.acp").make_safe(adapter)
  else
    return require("codecompanion.adapters.http").make_safe(adapter)
  end
end

-- Backwards compatibility: expose HTTP methods directly at root level
function M.set_model(adapter)
  return require("codecompanion.adapters.http").set_model(adapter)
end

return M
