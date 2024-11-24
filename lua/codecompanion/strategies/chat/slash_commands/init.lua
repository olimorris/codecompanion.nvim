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

---Set the provider to use for the Slash Command
---@param SlashCommand CodeCompanion.SlashCommand
---@param providers table
---@return function
function SlashCommands:set_provider(SlashCommand, providers)
  if SlashCommand.config.opts and SlashCommand.config.opts.provider then
    if not providers[SlashCommand.config.opts.provider] then
      return log:error(
        "Provider for the symbols slash command could not be found: %s",
        SlashCommand.config.opts.provider
      )
    end
    return providers[SlashCommand.config.opts.provider](SlashCommand) --[[@type function]]
  end
  return providers["default"] --[[@type function]]
end

---Execute the selected slash command
---@param item table The selected item from the completion menu
---@param chat CodeCompanion.Chat
---@return nil
function SlashCommands:execute(item, chat)
  local label = item.label:sub(2)
  log:debug("Executing slash command: %s", label)

  local callback = resolve(item.config.callback)
  if not callback then
    return log:error("Slash command not found: %s", label)
  end

  return callback
    .new({
      Chat = chat,
      config = item.config,
      context = item.context,
    })
    :execute(self)
end

return SlashCommands
