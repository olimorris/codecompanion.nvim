local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

local _CONSTANTS = {
  SUFFIX = "#",
}

---@param message string
---@param vars table
---@return string|nil
local function find(message, vars)
  for var, _ in pairs(vars) do
    if message:match("%f[%w" .. _CONSTANTS.SUFFIX .. "]" .. _CONSTANTS.SUFFIX .. var .. "%f[%W]") then
      return var
    end
  end
  return nil
end

---@param chat CodeCompanion.Chat
---@param rhs string|table|fun(self)
---@return table|nil
local function resolve(chat, rhs)
  local splits = vim.split(rhs, ".", { plain = true })
  local path = table.concat(splits, ".", 1, #splits - 1)
  local func = splits[#splits]

  local ok, module = pcall(require, "codecompanion." .. path)

  -- User is using a custom callback
  if not ok then
    log:trace("Calling variable: %s", path .. "." .. func)
    return require(path)[func](chat)
  end

  log:trace("Calling variable: %s", path .. "." .. func)
  return module[func](chat)
end

---@class CodeCompanion.Variables
---@field vars table
local Variables = {}

---@param args? table
function Variables.new(args)
  local self = setmetatable({
    vars = config.strategies.chat.variables,
    args = args,
  }, { __index = Variables })

  return self
end

---Parse a message to detect if it references any variables
---@param chat CodeCompanion.Chat
---@param message string
---@param index number
---@return table|nil
function Variables:parse(chat, message, index)
  local var = find(message, self.vars)
  if not var then
    return
  end
  log:debug("Variable found: %s", var)

  local found = self.vars[var]

  return {
    var = var,
    index = index,
    type = found.type,
    content = resolve(chat, found.callback),
  }
end

---Replace a variable in a given message
---@param message string
---@param vars table
---@return string
function Variables:replace(message, vars)
  var = _CONSTANTS.SUFFIX .. vars.var
  return vim.trim(message:gsub(var, ""))
end

return Variables
