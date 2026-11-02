local config = require("codecompanion.config")
local utils = require("codecompanion.utils")

local api = vim.api

---The user writes their prompt in an input split beneath the chat window, leaving the chat buffer read-only
---@class CodeCompanion.Chat.SplitPrompt : CodeCompanion.Chat.Prompt
---@field input CodeCompanion.Chat.UI.Input
---@field unsent? { row: number, lines: string[], builder_state: CodeCompanion.Chat.UI.BuilderState } The prompt written to the chat buffer but not yet sent
local SplitPrompt = {}

---@param args { chat: CodeCompanion.Chat }
---@return CodeCompanion.Chat.SplitPrompt
function SplitPrompt.new(args)
  return setmetatable({
    chat = args.chat,
    input = args.chat.ui.input,
    locks_chat_buffer = true,
    queues_messages = true,
  }, { __index = SplitPrompt }) ---@type CodeCompanion.Chat.SplitPrompt
end

---@return number[]
function SplitPrompt:get_bufnrs()
  return { self.chat.bufnr, self.input.bufnr }
end

---Send the keys that start writing in the chat buffer to the input instead
---@return nil
function SplitPrompt:set_keymaps()
  for _, key in ipairs({ "i", "a", "I", "A", "o", "O" }) do
    vim.keymap.set("n", key, function()
      self.input:focus()
    end, { buffer = self.chat.bufnr, desc = "Write in the input", nowait = true })
  end
end

---Start Tree-sitter parsing from the end of the chat buffer, where the next message is written
---@return nil
function SplitPrompt:set_header_line()
  self.chat.header_line = api.nvim_buf_line_count(self.chat.bufnr)
end

---@param args { content: string }
---@return nil
function SplitPrompt:add(args)
  self.input:add_prompt(args.content)
end

---Queue the prompt if the LLM is busy, otherwise write it into the chat buffer ready to send
---@return boolean should_submit
function SplitPrompt:prepare_submit()
  if self.chat._turn_in_progress or self.chat.current_request then
    self:_queue()
    return false
  end
  self:_write_to_chat_buffer()
  return true
end

---@return nil
function SplitPrompt:_queue()
  local prompt = self.input:get_prompt()
  if prompt == "" then
    return
  end

  self.chat:btw(prompt)
  self.input:clear_prompt()
  utils.notify("Message queued. It will be sent when the LLM is ready")
end

---@return nil
function SplitPrompt:_write_to_chat_buffer()
  local chat = self.chat
  local prompt = self.input:get_prompt()
  if prompt == "" then
    return
  end

  local is_first_message = api.nvim_buf_line_count(chat.bufnr) == 1
    and api.nvim_buf_get_lines(chat.bufnr, 0, 1, false)[1] == ""

  self.unsent = {
    row = is_first_message and 0 or api.nvim_buf_line_count(chat.bufnr),
    lines = self.input:get_lines(),
    builder_state = vim.deepcopy(chat.builder.state),
  }
  chat:add_buf_message(
    { role = config.constants.USER_ROLE, content = prompt },
    { force_role = true, type = chat.MESSAGE_TYPES.USER_MESSAGE }
  )
  self.input:clear_prompt()

  -- The builder spaces a header from the message above it, which a new chat doesn't have
  if is_first_message then
    chat.ui:unlock_buf()
    api.nvim_buf_set_lines(chat.bufnr, 0, 2, false, {})
    chat.ui:lock_buf()
    chat.builder.state.current_header_line = 0
  end
end

---@return nil
function SplitPrompt:mark_sent()
  self.unsent = nil
end

---Move a prompt that was prevented from being sent out of the chat buffer and back into the input
---@return nil
function SplitPrompt:undo_submit()
  local unsent = self.unsent
  if not unsent then
    return
  end
  self.unsent = nil

  self.chat.ui:unlock_buf()
  api.nvim_buf_set_lines(self.chat.bufnr, unsent.row, -1, false, {})
  self.chat.ui:lock_buf()

  self.chat.builder.state = unsent.builder_state
  self.chat._last_role = unsent.builder_state.last_role
  api.nvim_buf_set_lines(self.input.bufnr, 0, -1, false, unsent.lines)
end

---Move a queued message back into the input, above what the user is writing
---@return nil
function SplitPrompt:restore_queued()
  if self.chat._btw then
    self.input:prepend_prompt(self.chat._btw)
    self.chat._btw = nil
  end
end

---@return { tokens_row: number }
function SplitPrompt:start_next_message()
  local tokens_row = (self.chat.builder.state.current_header_line or 0) + 1
  self:set_header_line()
  return { tokens_row = tokens_row }
end

---@return nil
function SplitPrompt:make_editable() end

---@return nil
function SplitPrompt:clear()
  self.input:clear()
end

---@return nil
function SplitPrompt:close()
  self.input:close()
end

---@return nil
function SplitPrompt:apply_settings() end

---@param args { lines?: string[] }
---@return nil
function SplitPrompt:restore_lines(args)
  if args.lines then
    local lines = self.chat.ui:move_prompt_to_input(args.lines)
    self.chat.ui:unlock_buf()
    api.nvim_buf_set_lines(self.chat.bufnr, 0, -1, false, lines)
    self.chat.ui:lock_buf()
    self:set_header_line()
  end
  self.chat.context:render()
end

---@param args { line: string }
---@return nil
function SplitPrompt:add_context(args)
  self.input:add_context(args.line)
end

---@param args { lines: string[] }
---@return nil
function SplitPrompt:render_context(args)
  self.input:set_context(args.lines)
end

---@return nil
function SplitPrompt:clear_context()
  self.input:set_context({})
end

---@return nil
function SplitPrompt:fold_context() end

---@return string[]
function SplitPrompt:get_context()
  return self.input:get_context()
end

---The chat as the buffer layout would show it, so the draft in the input is saved and restored with the chat
---@return string[]
function SplitPrompt:get_session_lines()
  local lines = api.nvim_buf_get_lines(self.chat.bufnr, 0, -1, false)
  local draft = self.input:get_lines()
  if vim.trim(table.concat(draft, "\n")) == "" then
    return lines
  end

  if #lines == 1 and lines[1] == "" then
    lines = {}
  else
    table.insert(lines, "")
  end
  vim.list_extend(lines, { self.chat.ui:format_header(self.chat.ui.roles.user), "" })
  return vim.list_extend(lines, draft)
end

return SplitPrompt
