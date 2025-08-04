local config = require("codecompanion.config")
local helpers = require("codecompanion.strategies.chat.helpers")

local api = vim.api
local get_node_range = vim.treesitter.get_node_range --[[@as function]]
local get_node_text = vim.treesitter.get_node_text --[[@as function]]
local query_get = vim.treesitter.query.get --[[@as function]]

local user_role = config.strategies.chat.roles.user
local icons_path = config.display.chat.icons
local icons = {
  pinned = icons_path.pinned_buffer or icons_path.buffer_pin,
  watched = icons_path.watched_buffer or icons_path.buffer_watch,
}
local allowed_pins = {
  "<buf>",
  "<file>",
}
local allowed_watchers = {
  "<buf>",
}
local context_header = "> Context:"

---Parse the chat buffer to find where to add the context items
---@param chat CodeCompanion.Chat
---@return table|nil
local function ts_parse_buffer(chat)
  local query = query_get("markdown", "context")

  local tree = chat.parser:parse({ chat.header_line - 1, -1 })[1]
  local root = tree:root()

  -- Check if there are any context items already in the chat buffer
  local items
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "context" then
      items = node
    end
  end

  if items and not vim.tbl_isempty(chat.context_items) then
    local start_row, _, end_row, _ = items:range()
    return {
      capture = "context",
      start_row = start_row + 2,
      end_row = end_row + 1,
    }
  end

  -- If not, check if there is a heading to add the context items below
  local role
  local role_node
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = get_node_text(node, chat.bufnr)
      role_node = node
    end
  end

  role = helpers.format_role(role)

  if role_node and role == user_role then
    local start_row, _, end_row, _ = role_node:range()
    return {
      capture = "role",
      start_row = start_row + 1,
      end_row = end_row + 1,
    }
  end

  return nil
end

---Add context to the chat buffer
---@param chat CodeCompanion.Chat
---@param context CodeCompanion.Chat.ContextItem
---@param row integer
local function add(chat, context, row)
  if not context.opts.visible then
    return
  end
  local lines = {}

  -- Check if this context has special options and format accordingly
  local context_text
  if context.opts and context.opts.pinned then
    context_text = string.format("> - %s%s", icons.pinned, context.id)
  elseif context.opts and context.opts.watched then
    context_text = string.format("> - %s%s", icons.watched, context.id)
  else
    context_text = string.format("> - %s", context.id)
  end

  table.insert(lines, context_text)

  if vim.tbl_count(chat.context_items) == 1 then
    table.insert(lines, 1, context_header)
    table.insert(lines, "")
  end

  local was_locked = not vim.bo[chat.bufnr].modifiable
  if was_locked then
    chat.ui:unlock_buf()
  end
  api.nvim_buf_set_lines(chat.bufnr, row, row, false, lines)
  if was_locked then
    chat.ui:lock_buf()
  end
end

---@class CodeCompanion.Chat.Context
---@field Chat CodeCompanion.Chat
local Context = {}

---@class CodeCompanion.Chat.ContextArgs
---@field chat CodeCompanion.Chat

---@param args CodeCompanion.Chat.ContextArgs
function Context.new(args)
  local self = setmetatable({
    Chat = args.chat,
  }, { __index = Context })

  return self
end

---Add context to the chat buffer
---@param context CodeCompanion.Chat.ContextItem
---@return nil
function Context:add(context)
  if not context or not config.display.chat.show_context then
    return self
  end

  if context then
    context.opts = context.opts or {}

    -- Ensure both properties exist with defaults
    context.opts.pinned = context.opts.pinned or false
    context.opts.watched = context.opts.watched or false
    context.opts.visible = context.opts.visible

    if context.opts.visible == nil then
      context.opts.visible = config.display.chat.show_context
    end
    table.insert(self.Chat.context_items, context)
    -- If it's buffer context and it's being watched, start watching
    if context.bufnr and context.opts.watched then
      self.Chat.watchers:watch(context.bufnr)
    end
  end

  local parsed_buffer = ts_parse_buffer(self.Chat)

  if parsed_buffer then
    -- If the context block already exists, add to it
    if parsed_buffer.capture == "context" then
      add(self.Chat, context, parsed_buffer.end_row - 1)
      self:create_folds()
    -- If there are no context items then add a new block below the heading
    elseif parsed_buffer.capture == "role" then
      add(self.Chat, context, parsed_buffer.end_row + 1)
    end
  end
end

---Clear any context items from a message in the chat buffer before submission
---@param message table
---@return table
function Context:clear(message)
  if vim.tbl_isempty(self.Chat.context_items) or not config.display.chat.show_context then
    return message or nil
  end

  local parser = vim.treesitter.get_string_parser(message.content, "markdown")
  local query = query_get("markdown", "context")
  local root = parser:parse()[1]:root()

  local items = nil
  for id, node in query:iter_captures(root, message.content) do
    if query.captures[id] == "context" then
      items = node
    end
  end

  if items then
    local start_row, _, end_row, _ = items:range()
    message.content = vim.split(message.content, "\n")
    for i = start_row, end_row do
      message.content[i] = ""
    end
    message.content = vim.trim(table.concat(message.content, "\n"))
  end

  return message
end

---Get the range of the latest context block
---@param chat CodeCompanion.Chat
---@return number|nil, number|nil
local function get_range(chat)
  local query = query_get("markdown", "context")

  local tree = chat.parser:parse()[1]
  local root = tree:root()

  local role = nil
  local start_row, end_row = nil, nil

  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = helpers.format_role(get_node_text(node, chat.bufnr))
    elseif role == user_role and query.captures[id] == "context" then
      start_row, _, end_row, _ = get_node_range(node)
    end
  end

  return start_row, end_row
end

---Render all the context items in the chat buffer after a response from the LLM
---@return nil
function Context:render()
  local chat = self.Chat
  if vim.tbl_isempty(chat.context_items) then
    return self
  end
  local start_row = chat.header_line + 1

  local lines = {}
  table.insert(lines, context_header)

  for _, context in pairs(chat.context_items) do
    if not context or (context.opts and context.opts.visible == false) then
      goto continue
    end
    if context.opts and context.opts.pinned then
      table.insert(lines, string.format("> - %s%s", icons.pinned, context.id))
    elseif context.opts and context.opts.watched then
      table.insert(lines, string.format("> - %s%s", icons.watched, context.id))
    else
      table.insert(lines, string.format("> - %s", context.id))
    end
    ::continue::
  end
  if #lines == 1 then
    -- no context added
    return
  end
  table.insert(lines, "")

  api.nvim_buf_set_lines(chat.bufnr, start_row, start_row, false, lines)
  self:create_folds()
end

---Fold all of the context items in the chat buffer
---@return nil
function Context:create_folds()
  if not config.display.chat.fold_context then
    return
  end

  local start_row, end_row = get_range(self.Chat)
  if start_row and end_row then
    end_row = end_row - 1
    self.Chat.ui.folds:create_context_fold(self.Chat.bufnr, start_row, end_row, context_header)
  end
end

---Make a unique ID from the buffer number
---@param bufnr number
---@return string
function Context:make_id_from_buf(bufnr)
  local bufname = api.nvim_buf_get_name(bufnr)
  return vim.fn.fnamemodify(bufname, ":.")
end

---Determine if a context item can be pinned
---@param item string
---@return boolean
function Context:can_be_pinned(item)
  for _, pin in ipairs(allowed_pins) do
    if item:find(pin) then
      return true
    end
  end
  return false
end

---Determine if a context item can be watched
---@param item string
---@return boolean
function Context:can_be_watched(item)
  for _, watch in ipairs(allowed_watchers) do
    if item:find(watch) then
      return true
    end
  end
  return false
end

---Get the context items from the chat buffer
---@return table
function Context:get_from_chat()
  local query = query_get("markdown", "context")

  local tree = self.Chat.parser:parse()[1]
  local root = tree:root()

  local items = {}
  local role = nil

  local chat = self.Chat

  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = helpers.format_role(get_node_text(node, chat.bufnr))
    elseif role == user_role and query.captures[id] == "context_item" then
      local context = get_node_text(node, chat.bufnr)
      -- Clean both pinned and watched icons
      context = vim.iter(vim.tbl_values(icons)):fold(select(1, context:gsub("^> %- ", "")), function(acc, icon)
        return select(1, acc:gsub(icon, ""))
      end)
      table.insert(items, vim.trim(context))
    end
  end

  return items
end

return Context
