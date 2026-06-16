local session_titles = require("codecompanion.utils.session_titles")

---@class CodeCompanion.SlashCommand.Rename: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  return setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local function apply(title)
    title = title and vim.trim(title)
    if not title or title == "" then
      return
    end
    self.Chat.title_locked = true
    self.Chat:set_title(title)

    local connection = self.Chat.acp_connection
    if not connection or not connection.session_id then
      return
    end

    local sent = connection:send_session_title(title)
    if not sent then
      -- Local file backup
      session_titles.set(connection.session_id, title)
    end
  end

  if self.context and self.context.args and self.context.args ~= "" then
    return apply(self.context.args)
  end

  vim.ui.input({ prompt = "Rename chat: ", default = self.Chat.title or "" }, apply)
end

return SlashCommand
