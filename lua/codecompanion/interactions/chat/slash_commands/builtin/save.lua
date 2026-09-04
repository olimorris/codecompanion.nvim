local sessions = require("codecompanion.interactions.chat.sessions")
local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.Save: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  return setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })
end

---@param chat CodeCompanion.Chat
---@return boolean, string
function SlashCommand.enabled(chat)
  if not chat.adapter or chat.adapter.type ~= "http" then
    return false, "The /save command only supports HTTP chats"
  end
  return true, ""
end

---@return nil
function SlashCommand:execute()
  if vim.tbl_isempty(self.Chat.messages or {}) then
    return utils.notify("Nothing to save — chat is empty", vim.log.levels.WARN)
  end
  sessions.save(self.Chat)
end

return SlashCommand
