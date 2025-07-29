-- lua/codecompanion/cli_adapters/init.lua (updated to use shared utilities)
local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")

local M = {}

-- Registry of active adapters
local active_adapters = {}

---Get or create a CLI adapter
---@param name string
---@param opts table|nil
---@return table|nil
function M.get_adapter(name, opts)
  if active_adapters[name] and active_adapters[name]:is_running() then
    return active_adapters[name]
  end

  local adapter_config = adapter_utils.resolve_config(name, "cli", opts)
  if not adapter_config then
    log:error("Unknown CLI adapter: %s", name)
    return nil
  end

  -- Create the adapter using the RPC client
  local rpc = require("codecompanion.rpc")
  local adapter = rpc.new({
    name = adapter_config.name,
    command = adapter_utils.set_env_vars(adapter_config, adapter_config.command),
    protocol = adapter_config.protocol,
    parameters = adapter_config.parameters,
    opts = vim.tbl_extend("force", {
      env = {},
      timeout = 30000,
      auto_initialize = true,
    }, adapter_config.opts or {}),
    handlers = adapter_config.handlers,
    env = adapter_config.env,
    env_replaced = adapter_config.env_replaced,
  })

  -- Mix in the adapter configuration
  for k, v in pairs(adapter_config) do
    if k ~= "handlers" and k ~= "opts" and k ~= "command" then
      adapter[k] = v
    end
  end

  -- Add adapter-specific methods from handlers
  if adapter_config.handlers then
    for method_name, handler in pairs(adapter_config.handlers) do
      if
        method_name ~= "setup"
        and method_name ~= "initialize"
        and method_name ~= "notification"
        and method_name ~= "on_exit"
        and method_name ~= "teardown"
        and method_name ~= "session_update"
      then
        adapter[method_name] = function(self, ...)
          return handler(self, ...)
        end
      end
    end
  end

  if adapter:start() then
    active_adapters[name] = adapter
    return adapter
  end

  return nil
end

---Extend a CLI adapter configuration
---@param adapter table|string|function
---@param opts table|nil
---@return table
function M.extend(adapter, opts)
  return adapter_utils.extend(adapter, "cli", opts)
end

---Resolve a CLI adapter configuration
---@param adapter table|string|function
---@param opts table|nil
---@return table|nil
function M.resolve(adapter, opts)
  return adapter_utils.resolve_config(adapter, "cli", opts)
end

---Stop a specific adapter
---@param name string
---@return boolean success
function M.stop_adapter(name)
  if active_adapters[name] then
    local success = active_adapters[name]:stop()
    active_adapters[name] = nil
    return success
  end
  return true
end

---Stop all adapters
---@return boolean success
function M.stop_all()
  local success = true
  for name, adapter in pairs(active_adapters) do
    if not adapter:stop() then
      success = false
    end
  end
  active_adapters = {}
  return success
end

---List active adapters
---@return table
function M.list_active()
  local result = {}
  for name, adapter in pairs(active_adapters) do
    if adapter:is_running() then
      table.insert(result, name)
    end
  end
  return result
end

return M
