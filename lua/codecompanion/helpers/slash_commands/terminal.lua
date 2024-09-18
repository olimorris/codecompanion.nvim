CONSTANTS = {
  NAME = "Terminal Output",
}

---@class CodeCompanion.SlashCommandTerminal
local SlashCommandTerminal = {}

---@class CodeCompanion.SlashCommandTerminal
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu
function SlashCommandTerminal.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommandTerminal })

  return self
end

---Execute the slash command
---@return nil
function SlashCommandTerminal:execute()
  local terminal_buf = _G.codecompanion_last_terminal
  if not terminal_buf then
    return
  end
  local content = vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false)

  local Chat = self.Chat

  Chat:append_to_buf({ content = "[!" .. CONSTANTS.NAME .. "]\n" })
  Chat:append_to_buf({ content = "```\n" .. table.concat(content, "\n") .. "\n```\n" })
  Chat:fold_code()
end

return SlashCommandTerminal
