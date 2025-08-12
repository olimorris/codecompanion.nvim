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
---@param target? string
---@return table
local function resolve(chat, var_config, params, target)
  if type(var_config.callback) == "string" then
    local splits = vim.split(var_config.callback, ".", { plain = true })
    local path = table.concat(splits, ".", 1, #splits - 1)
    local variable = splits[#splits]

    local ok, module = pcall(require, "codecompanion." .. path .. "." .. variable)

    local init = {
      Chat = chat,
      config = var_config,
      params = params or (var_config.opts and var_config.opts.default_params),
      target = target,
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
      target = target,
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
---@param include_display_option? boolean Whether to include display options in the pattern
---@return string The compiled regex pattern
function Variables:_pattern(var, include_params, include_display_option)
  local base_pattern = CONSTANTS.PREFIX .. "{" .. var

  if include_display_option then
    base_pattern = base_pattern .. ":[^}]*"
  end

  base_pattern = base_pattern .. "}"

  if include_params then
    base_pattern = base_pattern .. "{[^}]*}"
  end

  return base_pattern
end

---Check a message for a variable and return all instances
---@param message table
---@return table|nil
function Variables:find(message)
  if not message.content then
    return nil
  end

  local found = {}
  local content = message.content

  for var, _ in pairs(self.vars) do
    local display_pattern = CONSTANTS.PREFIX .. "{" .. var .. ":([^}]*)}"
    for target in content:gmatch(display_pattern) do
      table.insert(found, {
        var = var,
        target = target,
      })
    end

    -- Check for regular syntax (#{var}) - but avoid duplicating display option matches
    local regular_pattern = CONSTANTS.PREFIX .. "{" .. var .. "}"
    local start_pos = 1
    while true do
      local match_start, match_end = content:find(regular_pattern, start_pos, true)
      if not match_start then
        break
      end

      -- Make sure this isn't part of a display option by checking if there's a colon before the brace
      local char_before_brace = content:sub(match_end - 1, match_end - 1)
      if char_before_brace ~= ":" then
        table.insert(found, {
          var = var,
          target = nil,
        })
      end

      start_pos = match_end + 1
    end
  end

  if #found == 0 then
    return nil
  end

  return found
end

---Parse a message to detect if it contains any variables
---@param chat CodeCompanion.Chat
---@param message table
---@return boolean
function Variables:parse(chat, message)
  local instances = self:find(message)
  if instances then
    for _, instance in ipairs(instances) do
      local var = instance.var
      local var_config = self.vars[var]
      log:debug("Variable found: %s (target: %s)", var, instance.target or "none")

      var_config["name"] = var

      if (var_config.opts and var_config.opts.contains_code) and not config.can_send_code() then
        log:warn("Sending of code has been disabled")
        goto continue
      end

      local target = instance.target
      local params = nil

      -- Check for regular params
      if var_config.opts and var_config.opts.has_params then
        params = find_params(message, var)
      end

      resolve(chat, var_config, params, target)

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
      -- Remove display option syntax first
      message = regex.replace(message, self:_pattern(var, true, true), "")
      message = regex.replace(message, self:_pattern(var, false, true), "")

      -- Then remove regular syntax
      message = regex.replace(message, self:_pattern(var, true), "")
      message = vim.trim(regex.replace(message, self:_pattern(var), ""))
    end
  end
  return message
end

return Variables
