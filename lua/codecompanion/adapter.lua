---@class CodeCompanion.Adapter
---@field name string
---@field url string
---@field header table
---@field parameters table
---@field schema table
local Adapter = {}

---@class CodeCompanion.AdapterArgs
---@field name string
---@field url string
---@field header table
---@field parameters table
---@field schema table

---@param args table
---@return CodeCompanion.Adapter
function Adapter.new(args)
  return setmetatable(args, { __index = Adapter })
end

---@param settings table
---@return CodeCompanion.Adapter
function Adapter:set_params(settings)
  -- TODO: Need to take into account the schema's "mapping" field
  for k, v in pairs(settings) do
    self.parameters[k] = v
  end

  return self
end

return Adapter
