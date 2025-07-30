local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local shared = require("codecompanion.adapters.shared")
local utils = require("codecompanion.utils.adapters")

---@class CodeCompanion.ACPAdapter
---@field name string The name of the adapter
---@field type string|"acp" The type of the adapter, e.g. "http" or "acp"
---@field formatted_name string The formatted name of the adapter
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field command table The command to trigger the ACP adapter
---@field defaults? table Additional options for the adapter
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field parameters? table The parameters to pass to the request
---@field handlers table Functions which link the output from the request to CodeCompanion
---@field handlers.setup? fun(self: CodeCompanion.ACPAdapter): boolean
---@field handlers.on_exit? fun(self: CodeCompanion.ACPAdapter, data: table): table|nil
---@field handlers.teardown? fun(self: CodeCompanion.ACPAdapter): any
---@field protocol? table Implement the ACP protocol in the adapter
---@field protocol.authenticate? fun(self: CodeCompanion.ACPAdapter): nil Authenticate with the adapter via ACP
---@field protocol.new_session? fun(self: CodeCompanion.ACPAdapter): nil Start a new ACP session with the adapter
---@field protocol.load_session? fun(self: CodeCompanion.ACPAdapter): nil Load a previously saved ACP session
---@field protocol.prompt? fun(self: CodeCompanion.ACPAdapter, messages: table): table Prompt the ACP adapter with messages
---@field protocol.agent_state? fun(self: CodeCompanion.ACPAdapter): nil TODO: To be implemented
---@field protocol.session_update? fun(self: CodeCompanion.ACPAdapter): nil TODO: To be implemented

---@class CodeCompanion.ACPAdapter
local Adapter = {}

---@return CodeCompanion.ACPAdapter
function Adapter.new(args)
  return setmetatable(args, { __index = Adapter })
end

Adapter.map_roles = shared.map_roles

---Extend an existing adapter
---@param adapter table|string|function
---@param opts? table
---@return CodeCompanion.ACPAdapter
function Adapter.extend(adapter, opts)
  local ok
  local adapter_config
  opts = opts or {}

  if type(adapter) == "string" then
    ok, adapter_config = pcall(require, "codecompanion.adapters.acp." .. adapter)
    if not ok then
      adapter_config = config.adapters[adapter]
      if type(adapter_config) == "function" then
        adapter_config = adapter_config()
      end
    end
  elseif type(adapter) == "function" then
    adapter_config = adapter()
  else
    adapter_config = adapter
  end

  if not adapter_config then
    return log:error("Adapter not found: %s", adapter)
  end

  adapter_config = vim.tbl_deep_extend("force", {}, vim.deepcopy(adapter_config), opts or {})

  return Adapter.new(adapter_config)
end

---Resolve an adapter from deep within the plugin...somewhere
---@param adapter? CodeCompanion.ACPAdapter|string|function
---@param opts? table
---@return CodeCompanion.ACPAdapter
function Adapter.resolve(adapter, opts)
  adapter = adapter or config.strategies.chat.adapter
  opts = opts or {}

  if type(adapter) == "table" then
    if (adapter.type and adapter.type ~= "acp") or not adapter.type then
      log:error("[ACP Adapter] Adapter is not an ACP adapter")
      error("Adapter is not an ACP adapter")
    end
    if adapter.name and Adapter.resolved(adapter) then
      log:trace("[ACP Adapter] Returning existing resolved adapter: %s", adapter.name)
      adapter = Adapter.new(adapter)
    elseif adapter.name then
      log:trace("[ACP Adapter] Table adapter: %s", adapter.name)
      adapter = Adapter.resolve(adapter.name)
    end
    adapter = Adapter.new(adapter)
  elseif type(adapter) == "string" then
    if not config.adapters.acp or not config.adapters.acp[adapter] then
      log:error("[ACP Adapter] Adapter not found: %s", adapter)
      error("Adapter not found: " .. adapter)
    end
    adapter = Adapter.extend(config.adapters.acp[adapter] or adapter, opts)
  elseif type(adapter) == "function" then
    adapter = adapter()
  end

  return adapter
end

---Check if an adapter has already been resolved
---@param adapter CodeCompanion.ACPAdapter|string|function|nil
---@return boolean
function Adapter.resolved(adapter)
  if adapter and getmetatable(adapter) and getmetatable(adapter).__index == Adapter then
    return true
  end
  return false
end

---Make an adapter safe for serialization
---@param adapter CodeCompanion.ACPAdapter
---@return table
function Adapter.make_safe(adapter)
  return {
    name = adapter.name,
    formatted_name = adapter.formatted_name,
    type = adapter.type,
    command = adapter.command,
    defaults = adapter.defaults,
    params = adapter.parameters,
    handlers = adapter.handlers,
  }
end

return Adapter
