local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.Command: CodeCompanion.SlashCommand
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

---Is the slash command enabled?
---@param chat CodeCompanion.Chat
---@return boolean,string
function SlashCommand.enabled(chat)
  return vim.tbl_count(chat.adapter.commands) > 1,
    "The command slash command is only available for ACP adapters with defined commands."
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local Chat = self.Chat

  local choices = {}
  vim
    .iter(Chat.adapter.commands)
    :filter(function(k, _)
      return k ~= "selected"
    end)
    :map(function(key, _)
      if type(key) == "string" then
        return key
      end
    end)
    :each(function(m)
      table.insert(choices, m)
    end)

  table.sort(choices)

  vim.ui.select(choices, {
    prompt = "Select Command",
    kind = "codecompanion.nvim",
  }, function(selected)
    if not selected then
      return
    end
    local command = Chat.adapter.commands[selected]
    if command then
      Chat.adapter.commands.selected = command
      Chat.acp_connection = nil
      require("codecompanion.interactions.chat.helpers").create_acp_connection(Chat)
      utils.notify(string.format("Switched to `%s` command", selected))
    end
  end)
end

return SlashCommand
