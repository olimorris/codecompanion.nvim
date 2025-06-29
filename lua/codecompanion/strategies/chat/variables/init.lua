local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local regex = require("codecompanion.utils.regex")

local CONSTANTS = {
  PREFIX = "#",
}

---Check a message for any parameters that have been given to the variable
---@param message table
---@param var string
---@return string|nil
local function find_params(message, var)
  local pattern = CONSTANTS.PREFIX .. "{" .. var .. "}{([^}]*)}"
  local params = message.content:match(pattern)
  if params then
    log:trace("Params found for variable: %s", params)
    return params
  end
  return nil
end

---@param chat CodeCompanion.Chat
---@param var_config table
---@param params? string
---@return table
local function resolve(chat, var_config, params)
  if type(var_config.callback) == "string" then
    local splits = vim.split(var_config.callback, ".", { plain = true })
    local path = table.concat(splits, ".", 1, #splits - 1)
    local variable = splits[#splits]

    local ok, module = pcall(require, "codecompanion." .. path .. "." .. variable)

    local init = {
      Chat = chat,
      config = var_config,
      params = params or (var_config.opts and var_config.opts.default_params),
    }

    -- User is using a custom callback
    if not ok then
      log:trace("Calling variable: %s", path .. "." .. variable)
      return require(path .. "." .. variable).new(init):output()
    end

    log:trace("Calling variable: %s", path .. "." .. variable)
    return module.new(init):output()
  end

  return require("codecompanion.strategies.chat.variables.user")
    .new({
      Chat = chat,
      config = var_config,
      params = params,
    })
    :output()
end

---@class CodeCompanion.Variables
local Variables = {}

function Variables.new()
  local self = setmetatable({
    vars = config.strategies.chat.variables,
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

---Check a message for a variable
---@param message table
---@return table|nil
function Variables:find(message)
  if not message.content then
    return nil
  end

  local found = {}
  for var, _ in pairs(self.vars) do
    if regex.find(message.content, self:_pattern(var)) then
      table.insert(found, var)
    end
  end

  if #found == 0 then
    return nil
  end

  return found
end

---Parse a message to detect if it references any variables
---@param chat CodeCompanion.Chat
---@param message table
---@return boolean
function Variables:parse(chat, message)
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

      local params = nil
      if var_config.opts and var_config.opts.has_params then
        params = find_params(message, var)
      end

      resolve(chat, var_config, params)

      ::continue::
    end

    return true
  end

  return false
end

---Replace a variable in a given message
---@param message string
---@param bufnr number
---@return string
function Variables:replace(message, bufnr)
  for var, _ in pairs(self.vars) do
    -- The buffer variable is unique because it can take parameters which need to be handled
    -- TODO: If more variables have parameters in the future we'll extract this
    if var:match("^buffer") then
      message = require("codecompanion.strategies.chat.variables.buffer").replace(CONSTANTS.PREFIX, message, bufnr)
    else
      message = regex.replace(message, self:_pattern(var, true), "")
      message = vim.trim(regex.replace(message, self:_pattern(var), ""))
    end
  end
  return message
end

return Variables
