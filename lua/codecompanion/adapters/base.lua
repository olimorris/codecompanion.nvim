local utils = require("codecompanion.utils.adapters")

---@class CodeCompanion.AdapterInterface
---@field name string The name of the adapter
---@field type string The type of adapter ("http" | "cli")
---@field roles table The mapping of roles
---@field map_roles fun(self, messages: table): table
---@field resolve fun(adapter: any, opts?: table): CodeCompanion.Adapter
---@field resolved fun(adapter: any): boolean
---@field extend fun(adapter: any, opts?: table): CodeCompanion.Adapter
---@field make_safe fun(adapter: CodeCompanion.Adapter): table
local BaseAdapter = {}

---Replace roles in the messages with the adapter's defined roles
---@param messages table
---@return table
function BaseAdapter:map_roles(messages)
  return utils.map_roles(self.roles, messages)
end

---Extend an existing adapter (to be implemented by subclasses)
---@param adapter table|string|function
---@param opts? table
---@return CodeCompanion.Adapter
function BaseAdapter.resolve(adapter, opts)
  error("extend() must be implemented by adapter subclass")
end

---Check if an adapter has already been resolved
---@param adapter any
---@return boolean
function BaseAdapter.resolved(adapter)
  if adapter and getmetatable(adapter) and getmetatable(adapter).__index then
    local mt = getmetatable(adapter).__index
    return mt == BaseAdapter or (mt.map_roles and mt.resolved and mt.extend and mt.make_safe)
  end
  return false
end

---Extend an existing adapter (to be implemented by subclasses)
---@param adapter table|string|function
---@param opts? table
---@return CodeCompanion.Adapter
function BaseAdapter.extend(adapter, opts)
  error("extend() must be implemented by adapter subclass")
end

---Make an adapter safe for serialization (to be implemented by subclasses)
---@param adapter CodeCompanion.Adapter
---@return table
function BaseAdapter.make_safe(adapter)
  error("make_safe() must be implemented by adapter subclass")
end

return BaseAdapter
