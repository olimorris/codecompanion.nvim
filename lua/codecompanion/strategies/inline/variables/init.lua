---@class CodeCompanion.Inline.Variable
---@field config table
---@field inline CodeCompanion.Inline
---@field vars table
---@field prompt string The user prompt to check for variables

---@class CodeCompanion.Inline.Variables
---@field context table

---@class CodeCompanion.Inline.VariablesArgs
---@field context table

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  PREFIX = "#",
}

---@class CodeCompanion.Inline.Variable
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
---@return CodeCompanion.Inline.Variable
function Variables:find()
  for var, _ in pairs(self.config) do
    if self.prompt:match("%f[%w" .. CONSTANTS.PREFIX .. "]" .. CONSTANTS.PREFIX .. var .. "%f[%W]") then
      table.insert(self.vars, var)
    end
  end

  return self
end

---Replace variables in the prompt
---@return CodeCompanion.Inline.Variable
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
    local var_config = self.config[var]
    local callback = var_config.callback

    -- Resolve them and add them to the outputs
    local ok, module = pcall(require, "codecompanion." .. callback)
    if ok then
      var_output = module --[[@type CodeCompanion.Inline.Variables]]
      goto append
    end

    ok, module = pcall(loadfile, callback)
    if not ok then
      log:error("[Variables] %s could not be resolved", var)
      goto skip
    end
    if module then
      var_output = module() --[[@type CodeCompanion.Inline.Variables]]
    end

    if (var_config.opts and var_config.opts.contains_code) and not config.can_send_code() then
      log:warn("Sending of code has been disabled")
      goto skip
    end

    ::append::

    local output = var_output.new({ context = self.inline.context }):output()
    if output then
      table.insert(outputs, output)
    end

    ::skip::
  end

  return outputs
end

return Variables
