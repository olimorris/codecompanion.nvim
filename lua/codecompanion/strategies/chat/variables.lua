local _CONSTANTS = {
  SUFFIX = "#",
}

---@class CodeCompanion.Variables
local Variables = {}

---@param opts table
function Variables.new(opts)
  local self = setmetatable({}, { __index = Variables })
  self.opts = opts

  return self
end

---Parse a message to detect if it references any variables
---@param message string
---@param index number
---@return table
function Variables:parse(message, index) end

return Variables
