local config = require("codecompanion").config

local _CONSTANTS = {
  SUFFIX = "#",
}

---@class CodeCompanion.Variables
local Variables = {}

---@param args? table
function Variables.new(args)
  local self = setmetatable({
    opts = config.strategies.chat.variables,
  }, { __index = Variables })

  return self
end

---Parse a message to detect if it references any variables
---@param message string
---@param index number
---@return table
function Variables:parse(message, index) end

return Variables
