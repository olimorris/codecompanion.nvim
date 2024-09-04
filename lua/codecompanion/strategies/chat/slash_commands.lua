local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

---Resolve the callback to the correct module
---@param callback string The module to get
---@return table
local function resolve(callback)
  log:debug("Resolving slash command: %s", callback)
  local ok, slash_command = pcall(require, "codecompanion." .. callback)
  if not ok then
    slash_command = require(callback)
  end

  return slash_command
end

---@class CodeCompanion.SlashCommands
local SlashCommands = {}

---@class CodeCompanion.SlashCommands
function SlashCommands.new()
  return setmetatable({}, { __index = SlashCommands })
end

---Execute the selected slash command
---@param item table The selected item from the completion menu
---@return nil
function SlashCommands:execute(item)
  local label = item.label:sub(2)
  log:debug("Executing slash command: %s", label)

  local callback = resolve(item.config.callback)
  if not callback then
    return log:error("Slash command not found: %s", label)
  end

  --TODO: Enable callbacks to be functions
  --We can then pass in the Chat and context to the callback

  return callback
    .new({
      config = item.config,
      Chat = item.Chat,
      context = item.context,
    })
    :execute(item)
end

return SlashCommands
