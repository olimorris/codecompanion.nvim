local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  PREFIX = "#",
}

---@class CodeCompanion.Inline.Variables: CodeCompanion.Variables
---@field config table
---@field inline CodeCompanion.Inline
---@field vars table
---@field prompt string
local Variables = {}

function Variables.new(args)
  local self = setmetatable({
    config = config.strategies.inline.variables,
    inline = args.inline,
    prompt = args.prompt,
    vars = {},
  }, { __index = Variables })

  return self
end

---Check a prompt for a variable
---@return CodeCompanion.Inline.Variables
function Variables:find()
  for var, _ in pairs(self.config) do
    if self.prompt:match("%f[%w" .. CONSTANTS.PREFIX .. "]" .. CONSTANTS.PREFIX .. var .. "%f[%W]") then
      table.insert(self.vars, var)
    end
  end

  return self
end

---Replace variables in the prompt
---@return CodeCompanion.Inline.Variables
function Variables:replace()
  for var, _ in pairs(self.config) do
    self.prompt = vim.trim(self.prompt:gsub(CONSTANTS.PREFIX .. var .. " ", ""))
  end
  return self
end

---Add the variables to the inline class
---@return nil
function Variables:add()
  -- Loop through the found variables
  for _, var in ipairs(self.vars) do
    if not self.config[var] then
      return log:error("The variable `%s` is not defined in the config", var)
    end
    -- Resolve them
    local ok, module = pcall(require, "codecompanion." .. self.config[var].callback)
    if not ok then
      return log:error("Could not find the callback for `%s`", var)
    end

    -- Call them
    local output = module(self.inline.context)

    -- Add their output to the inline class
  end
end

return Variables
