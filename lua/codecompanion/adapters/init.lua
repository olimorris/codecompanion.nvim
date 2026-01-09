local config = require("codecompanion.config")

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
---@param args { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter, acp_connection?: CodeCompanion.ACP.Connection, model?: string }
---@return CodeCompanion.HTTPAdapter
function M.set_model(args)
  if adapter_type(args.adapter) == "acp" then
    return require("codecompanion.adapters.acp").set_model(args)
  end
  return require("codecompanion.adapters.http").set_model(args)
end

---Get a handler function from an adapter with backwards compatibility
---@param adapter CodeCompanion.HTTPAdapter
---@param handler_name string
---@return nil
function M.get_handler(adapter, handler_name)
  return require("codecompanion.adapters.http").get_handler(adapter, handler_name)
end

---Call a handler on an adapter with backwards compatibility
---@param adapter CodeCompanion.HTTPAdapter
---@param handler_name string
---@param ... any Additional arguments to pass to the handler
---@return any|nil
function M.call_handler(adapter, handler_name, ...)
  local handler = M.get_handler(adapter, handler_name)
  if handler then
    return handler(adapter, ...)
  end
  return nil
end

return M
