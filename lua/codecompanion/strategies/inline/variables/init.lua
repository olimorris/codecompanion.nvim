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
local regex = require("codecompanion.utils.regex")

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

---Creates a regex pattern to match a variable in a message
---@param var string The variable name to create a pattern for
---@param include_params? boolean Whether to include parameters in the pattern
---@return string The compiled regex pattern
function Variables:_pattern(var, include_params)
  return CONSTANTS.PREFIX .. "{" .. var .. "}" .. (include_params and "{[^}]*}" or "")
end

---Check a prompt for a variable
---@return CodeCompanion.Inline.Variable
function Variables:find()
  for var, _ in pairs(self.config) do
    if regex.find(self.prompt, self:_pattern(var)) then
      table.insert(self.vars, var)
    end
  end

  return self
end

---Replace variables in the prompt
---@return CodeCompanion.Inline.Variable
function Variables:replace()
  for var, _ in pairs(self.config) do
    self.prompt = vim.trim(regex.replace(self.prompt, self:_pattern(var), ""))
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

    if type(callback) == "function" then
      local ok, output = pcall(callback, self)
      if not ok then
        log:error("[Variables] %s could not be resolved: %s", var, output)
      else
        if output then
          table.insert(outputs, output)
        end
      end
      goto skip
    end

    -- Resolve them and add them to the outputs
    local ok, module = pcall(require, "codecompanion." .. callback)
    if ok then
      var_output = module --[[@type CodeCompanion.Inline.Variables]]
      goto append
    end

    do
      local err
      module, err = loadfile(callback)
      if err then
        log:error("[Variables] %s could not be resolved", var)
        goto skip
      end
      if module then
        var_output = module() --[[@type CodeCompanion.Inline.Variables]]
      end
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
