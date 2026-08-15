local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.Rename: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommand
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local Chat = self.Chat

  vim.ui.input({
    prompt = "Enter title: ",
    default = Chat.title or "",
  }, function(input)
    if input then
      Chat:set_title(input)
      return utils.notify("Renamed the chat")
    end
  end)
end

return SlashCommand
