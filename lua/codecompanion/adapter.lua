---@class CodeCompanion.Adapter
---@field data table
local Adapter = {}

---@class CodeCompanion.AdapterArgs
---@field args table

---@param args CodeCompanion.AdapterArgs
---@return CodeCompanion.Adapter
function Adapter.new(args)
  return setmetatable({ data = args }, { __index = Adapter })
end

function Adapter:process(settings)
  for k, v in pairs(self.data.payload) do
    if type(v) == "string" then
      -- Attempt to extract the key assuming the format is always `${key}`
      local name, _ = v:find("%${.+}")
      if name then
        local key = v:sub(3, -2) -- Extract the key without `${` and `}`
        if settings[key] ~= nil then
          self.data.payload[k] = settings[key]
        else
          self.data.payload[k] = nil
        end
      end
    end
  end

  return self
end

return Adapter
