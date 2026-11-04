local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.helpers")
local parser = require("codecompanion.interactions.chat.parser")

local api = vim.api
local get_node_range = vim.treesitter.get_node_range --[[@as function]]
local get_node_text = vim.treesitter.get_node_text --[[@as function]]
local query_get = vim.treesitter.query.get --[[@as function]]

local CONTEXT_HEADER = require("codecompanion.interactions.chat.context").HEADER

---Set chat buffer lines while preserving its edit lock
---@param chat CodeCompanion.Chat
---@param opts { start_row: number, end_row: number, lines: string[] }
local function set_chat_buffer_lines(chat, opts)
  local was_locked = not vim.bo[chat.bufnr].modifiable
  if was_locked then
    chat.ui:unlock_buf()
  end

  api.nvim_buf_set_lines(chat.bufnr, opts.start_row, opts.end_row, false, opts.lines)

  if was_locked then
    chat.ui:lock_buf()
  end
end

---Find where in the user's message the next context item belongs
---@param chat CodeCompanion.Chat
---@return { capture: "context"|"role", start_row: number, end_row: number }|nil
local function find_context_position(chat)
  local query = query_get("markdown", "cc_context")

  local tree = chat.parsers.markdown:parse({ chat.header_line - 1, -1 })[1]
  local root = tree:root()

  local items
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "context" then
      items = node
    end
  end

  if items and not vim.tbl_isempty(chat.context_items) then
    local start_row, _, end_row, _ = items:range()
    return { capture = "context", start_row = start_row + 2, end_row = end_row + 1 }
  end

  local role
  local role_node
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = get_node_text(node, chat.bufnr)
      role_node = node
    end
  end

  if role_node and helpers.format_role(role) == config.interactions.chat.roles.user then
    local start_row, _, end_row, _ = role_node:range()
    return { capture = "role", start_row = start_row + 1, end_row = end_row + 1 }
  end

  return nil
end

---Get the range of the context block under the latest user header
---@param chat CodeCompanion.Chat
---@return { start_row: number, end_row: number }|nil
local function find_context_block(chat)
  local query = query_get("markdown", "cc_context")
  local root = chat.parsers.markdown:parse()[1]:root()

  local role
  local block
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = helpers.format_role(get_node_text(node, chat.bufnr))
    elseif role == config.interactions.chat.roles.user and query.captures[id] == "context" then
      local start_row, _, end_row, _ = get_node_range(node)
      block = { start_row = start_row, end_row = end_row }
    end
  end

  return block
end

---The user writes their prompt at the bottom of the chat buffer, beneath their header
---@class CodeCompanion.Chat.BufferPrompt : CodeCompanion.Chat.Prompt
local BufferPrompt = {}

---@param args { chat: CodeCompanion.Chat }
---@return CodeCompanion.Chat.BufferPrompt
function BufferPrompt.new(args)
  return setmetatable({
    chat = args.chat,
    locks_chat_buffer = false,
    queues_messages = false,
  }, { __index = BufferPrompt }) ---@type CodeCompanion.Chat.BufferPrompt
end

---@return number[]
function BufferPrompt:get_bufnrs()
  return { self.chat.bufnr }
end

---@return nil
function BufferPrompt:set_keymaps() end

---Locate the last user header in a restored chat, so Tree-sitter parsing starts from it
---@param args { messages?: CodeCompanion.Chat.Messages }
---@return nil
function BufferPrompt:set_header_line(args)
  if args.messages and vim.tbl_count(args.messages) > 0 then
    local header_line = parser.headers(self.chat)
    self.chat.header_line = header_line and (header_line + 1) or 1
  end
end

---@param args { content: string }
---@return nil
function BufferPrompt:add(args)
  self.chat:add_buf_message({ role = config.constants.USER_ROLE, content = args.content })
end

---@return boolean
function BufferPrompt:prepare_submit()
  return true
end

---@return nil
function BufferPrompt:mark_sent() end

---@return nil
function BufferPrompt:undo_submit() end

---@return nil
function BufferPrompt:restore_queued() end

---Write the user's header for their next message
---@return { tokens_row: number }
function BufferPrompt:start_next_message()
  self.chat:add_buf_message({ role = config.constants.USER_ROLE, content = "" })
  self.chat.header_line = (self.chat.builder.state.current_header_line or 0) + 1
  return { tokens_row = self.chat.header_line }
end

---@return nil
function BufferPrompt:make_editable()
  self.chat.ui:unlock_buf()
end

---@return nil
function BufferPrompt:clear() end

---@return nil
function BufferPrompt:close() end

---Apply any settings the user has changed at the top of the chat buffer
---@return nil
function BufferPrompt:apply_settings()
  if not config.display.chat.show_settings then
    return
  end
  local settings = parser.settings(self.chat.bufnr, self.chat.parsers.yaml, self.chat.adapter)
  helpers.apply_settings_and_model(self.chat, settings)
end

---@param args { lines?: string[] }
---@return nil
function BufferPrompt:restore_lines(args)
  -- The saved markdown already carries the context block, so replant rather than re-render
  if args.lines then
    api.nvim_buf_set_lines(self.chat.bufnr, 0, -1, false, args.lines)
  end
  self:fold_context()
end

---Add a context item beneath the user's header, starting the context block if there isn't one
---@param args { line: string }
---@return nil
function BufferPrompt:add_context(args)
  local position = find_context_position(self.chat)
  if not position then
    return
  end

  local lines = { args.line }
  if vim.tbl_count(self.chat.context_items) == 1 then
    table.insert(lines, 1, CONTEXT_HEADER)
    table.insert(lines, "")
  end

  local row = position.capture == "context" and position.end_row - 1 or position.end_row + 1
  set_chat_buffer_lines(self.chat, { start_row = row, end_row = row, lines = lines })
  if position.capture == "context" then
    self:fold_context()
  end
end

---@param args { lines: string[] }
---@return nil
function BufferPrompt:render_context(args)
  local start_row = self.chat.header_line + 1
  set_chat_buffer_lines(
    self.chat,
    { start_row = start_row, end_row = start_row, lines = vim.list_extend(args.lines, { "" }) }
  )
  self:fold_context()
end

---@return nil
function BufferPrompt:clear_context()
  local block = find_context_block(self.chat)
  if block then
    set_chat_buffer_lines(self.chat, { start_row = block.start_row, end_row = block.end_row + 1, lines = {} })
  end
end

---@return nil
function BufferPrompt:fold_context()
  if not config.display.chat.fold_context then
    return
  end

  local block = find_context_block(self.chat)
  if block then
    self.chat.ui.folds:create_context_fold(self.chat.bufnr, block.start_row, block.end_row - 1, CONTEXT_HEADER)
  end
end

---The context items listed under the latest user header
---@return string[]
function BufferPrompt:get_context()
  local chat = self.chat
  local query = query_get("markdown", "cc_context")
  local root = chat.parsers.markdown:parse()[1]:root()

  local items = {}
  local role
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = helpers.format_role(get_node_text(node, chat.bufnr))
    elseif role == config.interactions.chat.roles.user and query.captures[id] == "context_item" then
      table.insert(items, get_node_text(node, chat.bufnr))
    end
  end

  return items
end

---@return string[]
function BufferPrompt:get_session_lines()
  return api.nvim_buf_get_lines(self.chat.bufnr, 0, -1, false)
end

return BufferPrompt
