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

---Add the variables to the inline class as prompts
---@return table
function Variables:output()
  local outputs = {}

  -- Loop through the found variables
  for _, var in ipairs(self.vars) do
    if not self.config[var] then
      return log:error("[Variables] `%s` is not defined in the config", var)
    end

    local var_output
    local callback = self.config[var].callback

    -- Resolve them and add them to the outputs
    local ok, module = pcall(require, "codecompanion." .. callback)
    if ok then
      var_output = module
      goto append
    end

    ok, module = pcall(loadfile, callback)
    if not ok then
      log:error("[Variables] %s could not be resolved", var)
      goto skip
    end
    if module then
      var_output = module()
    end

    ::append::

    table.insert(outputs, var_output.new({ context = self.inline.context }):output())

    ::skip::
  end

  return outputs
end

return Variables
