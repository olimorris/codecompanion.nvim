---Where the user writes their prompt
---@class CodeCompanion.Chat.Prompt
---@field add fun(self, args: { content: string })
---@field add_context fun(self, args: { line: string })
---@field apply_settings fun(self)
---@field chat CodeCompanion.Chat
---@field clear fun(self)
---@field clear_context fun(self)
---@field close fun(self)
---@field fold_context fun(self)
---@field get_bufnrs fun(self): number[]
---@field get_context fun(self): string[]
---@field get_session_lines fun(self): string[]
---@field locks_chat_buffer boolean Whether the chat buffer stays read-only whilst the user writes their prompt
---@field make_editable fun(self)
---@field mark_sent fun(self)
---@field prepare_submit fun(self): boolean
---@field queues_messages boolean Whether submitting whilst the LLM is busy queues the message
---@field render_context fun(self, args: { lines: string[] })
---@field restore_lines fun(self, args: { lines?: string[] })
---@field restore_queued fun(self)
---@field set_header_line fun(self, args: { messages?: CodeCompanion.Chat.Messages })
---@field set_keymaps fun(self)
---@field start_next_message fun(self): { tokens_row: number }
---@field undo_submit fun(self)

local M = {}

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Chat.Prompt
function M.new(chat)
  local layout = chat.ui.input and "split" or "buffer"
  return require("codecompanion.interactions.chat.prompt." .. layout).new({ chat = chat })
end

return M
