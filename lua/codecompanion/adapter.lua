---@class CodeCompanion.Adapter
---@field url string
---@field header table
---@field payload table
---@field schema table
local Adapter = {}

---@class CodeCompanion.AdapterArgs
---@field url string
---@field header table
---@field payload table
---@field schema table

---@param args table
---@return CodeCompanion.Adapter
function Adapter.new(args)
  return setmetatable(args, { __index = Adapter })
end

---@param settings table
---@return CodeCompanion.Adapter
function Adapter:process(settings)
  for k, v in pairs(self.payload) do
    if type(v) == "string" then
      -- Attempt to extract the key assuming the format is always `${key}`
      local name, _ = v:find("%${.+}")
      if name then
        local key = v:sub(3, -2) -- Extract the key without `${` and `}`
        if settings[key] ~= nil then
          self.payload[k] = settings[key]
        else
          self.payload[k] = nil
        end
      end
    end
  end

  return self
end

return Adapter
