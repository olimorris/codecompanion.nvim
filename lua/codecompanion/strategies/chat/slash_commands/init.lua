local log = require("codecompanion.utils.log")

---Resolve the callback to the correct module
---@param callback string The module to get
---@return table|nil
local function resolve(callback)
  local ok, slash_command = pcall(require, "codecompanion." .. callback)
  if ok then
    log:debug("Calling slash command: %s", callback)
    return slash_command
  end

  -- Try loading the tool from the user's config
  ok, slash_command = pcall(loadfile, callback)
  if not ok then
    return log:error("Could not load the slash command: %s", callback)
  end

  if slash_command then
    log:debug("Calling slash command: %s", callback)
    return slash_command()
  end
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
