local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  PREFIX = "#",
}

---Check a message for any parameters that have been given to the variable
---@param message table
---@param var string
---@return string|nil
local function find_params(message, var)
  local pattern = CONSTANTS.PREFIX .. var .. ":([^%s]+)"

  local params = message.content:match(pattern)
  if params then
    log:trace("Params found for variable: %s", params)
    return params
  end

  return nil
end

---@param chat CodeCompanion.Chat
---@param callback table
---@param params? string
---@return table
local function resolve(chat, callback, params)
  local splits = vim.split(callback, ".", { plain = true })
  local path = table.concat(splits, ".", 1, #splits - 1)
  local variable = splits[#splits]

  local ok, module = pcall(require, "codecompanion." .. path .. "." .. variable)

  -- User is using a custom callback
  if not ok then
    log:trace("Calling variable: %s", path .. "." .. variable)
    return require(path .. "." .. variable).new({ chat = chat, params = params }):execute()
  end

  log:trace("Calling variable: %s", path .. "." .. variable)
  return module.new({ chat = chat, params = params }):execute()
end

---@class CodeCompanion.Variables
local Variables = {}

function Variables.new()
  local self = setmetatable({
    vars = config.strategies.chat.variables,
  }, { __index = Variables })

  return self
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
    if message.content:match("%f[%w" .. CONSTANTS.PREFIX .. "]" .. CONSTANTS.PREFIX .. var .. "%f[%W]") then
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

      local params = nil
      if var_config.opts and var_config.opts.has_params then
        params = find_params(message, var)
      end

      if (var_config.opts and var_config.opts.contains_code) and config.opts.send_code == false then
        log:debug("Sending of code disabled")
        return false
      end

      local id = chat.References:make_id_from_buf(chat.context.bufnr)

      chat:add_message({
        role = config.constants.USER_ROLE,
        content = resolve(chat, var_config.callback, params),
      }, { visible = false, reference = id, tag = "variable" })

      if var_config.opts and not var_config.opts.hide_reference then
        chat.References:add({
          source = "variable",
          name = var,
          id = id,
        })
      end
    end

    return true
  end

  return false
end

---Replace a variable in a given message
---@param message string
---@return string
function Variables:replace(message)
  for var, _ in pairs(self.vars) do
    message = vim.trim(message:gsub(CONSTANTS.PREFIX .. var, ""))
  end
  return message
end

return Variables
