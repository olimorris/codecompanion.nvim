local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  PREFIX = "#",
}

---@class CodeCompanion.Inline.Variables: CodeCompanion.Variables
---@field found table
---@field prompt string
local Variables = {}

function Variables.new(args)
  local self = setmetatable({
    found = {},
    prompt = args.prompt,
    vars = config.strategies.inline.variables,
  }, { __index = Variables })

  return self
end

---Check a prompt for a variable
---@return CodeCompanion.Inline.Variables
function Variables:find()
  for var, _ in pairs(self.vars) do
    if self.prompt:match("%f[%w" .. CONSTANTS.PREFIX .. "]" .. CONSTANTS.PREFIX .. var .. "%f[%W]") then
      table.insert(self.found, var)
    end
  end

  return self
end

---Replace a variable in a given prompt
---@return CodeCompanion.Inline.Variables
function Variables:replace()
  for var, _ in pairs(self.vars) do
    self.prompt = vim.trim(self.prompt:gsub(CONSTANTS.PREFIX .. var .. " ", ""))
  end
  return self
end

---Parse a message to detect if it references any variables
---@param inline CodeCompanion.Inline
---@param message table
---@return boolean
function Variables:parse(inline, message)
  local vars = self:find(message)
  if vars then
    for _, var in ipairs(vars) do
      local var_config = self.vars[var]
      log:debug("Variable found: %s", var)

      var_config["name"] = var

      if (var_config.opts and var_config.opts.contains_code) and not config.can_send_code() then
        log:warn("Sending of code has been disabled")
        goto continue
      end

      -- TODO: implement resolve

      ::continue::
    end

    return true
  end

  return false
end

return Variables
