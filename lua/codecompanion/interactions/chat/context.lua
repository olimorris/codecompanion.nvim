local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.helpers")

local api = vim.api
local get_node_range = vim.treesitter.get_node_range --[[@as function]]
local get_node_text = vim.treesitter.get_node_text --[[@as function]]
local query_get = vim.treesitter.query.get --[[@as function]]

local user_role = config.interactions.chat.roles.user
local icons = {
  sync_all = config.display.chat.icons.buffer_sync_all,
  sync_diff = config.display.chat.icons.buffer_sync_diff,
}

local allowed__all = {
  "<buf>",
  "<file>",
}
local allowed__diff = {
  "<buf>",
}
local context_header = "> Context:"

---Parse the chat buffer to find where to add the context items
---@param chat CodeCompanion.Chat
---@return table|nil
local function ts_parse_buffer(chat)
  local query = query_get("markdown", "cc_context")

  local tree = chat.chat_parser:parse({ chat.header_line - 1, -1 })[1]
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
---@param row number
local function add(chat, context, row)
  if not context.opts.visible then
    return
  end
  local lines = {}

  -- Check if this context has special options and format accordingly
  local context_text
  if context.opts and context.opts.sync_all then
    context_text = string.format("> - %s%s", icons.sync_all, context.id)
  elseif context.opts and context.opts.sync_diff then
    context_text = string.format("> - %s%s", icons.sync_diff, context.id)
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

---@class CodeCompanion.Chat.ContextItem
---@field bufnr? number The buffer number if this is buffer context
---@field id string The unique ID of the context which links it to a message in the chat buffer and is displayed to the user
---@field source string The source of the context e.g. slash_command
---@field opts? table
---@field opts.sync_all? boolean When synced, whether the entire buffer is shared
---@field opts.sync_diff? boolean When synced, whether only buffer diffs are shared
---@field opts.visible? boolean Whether this context item should be shown in the chat UI

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
    context.opts.sync_all = context.opts.sync_all or false
    context.opts.sync_diff = context.opts.sync_diff or false
    context.opts.visible = context.opts.visible

    if context.opts.visible == nil then
      context.opts.visible = config.display.chat.show_context
    end
    table.insert(self.Chat.context_items, context)
    if context.bufnr and context.opts.sync_diff then
      self.Chat.buffer_diffs:sync(context.bufnr)
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

---Remove any context items from a message in the chat buffer before submission
---@param message table
---@return table
function Context:remove(message)
  if vim.tbl_isempty(self.Chat.context_items) or not config.display.chat.show_context then
    return message or nil
  end

  local parser = vim.treesitter.get_string_parser(message.content, "markdown")
  local query = query_get("markdown", "cc_context")
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
  local query = query_get("markdown", "cc_context")

  local tree = chat.chat_parser:parse()[1]
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
    if context.opts and context.opts.sync_all then
      table.insert(lines, string.format("> - %s%s", icons.sync_all, context.id))
    elseif context.opts and context.opts.sync_diff then
      table.insert(lines, string.format("> - %s%s", icons.sync_diff, context.id))
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

---Clear the rendered context block from the chat buffer (if present)
---@return CodeCompanion.Chat.Context
function Context:clear_rendered()
  local start_row, end_row = get_range(self.Chat)
  if not start_row or not end_row then
    return self
  end

  api.nvim_buf_set_lines(self.Chat.bufnr, start_row, end_row + 1, false, {})

  return self
end

---Remove context items by their IDs and re-render the context block
---@param ids table<string, boolean> A set of IDs to remove
---@return nil
function Context:remove_items(ids)
  self.Chat.context_items = vim
    .iter(self.Chat.context_items)
    :filter(function(ctx)
      return not ids[ctx.id]
    end)
    :totable()

  if self.Chat.bufnr and api.nvim_buf_is_valid(self.Chat.bufnr) then
    self:clear_rendered()
    self:render()
  end
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

---Determine if a context item can be synced and all of its content shared
---@param item string
---@return boolean
function Context:can_be_synced__all(item)
  for _, sync in ipairs(allowed__all) do
    if item:find(sync) then
      return true
    end
  end
  return false
end

---Determine if a context item can be synced and its diff shared
---@param item string
---@return boolean
function Context:can_be_synced__diff(item)
  for _, sync in ipairs(allowed__diff) do
    if item:find(sync) then
      return true
    end
  end
  return false
end

---Get the context items from the chat buffer
---@return table
function Context:get_from_chat()
  local query = query_get("markdown", "cc_context")

  local tree = self.Chat.chat_parser:parse()[1]
  local root = tree:root()

  local items = {}
  local role = nil

  local chat = self.Chat

  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = helpers.format_role(get_node_text(node, chat.bufnr))
    elseif role == user_role and query.captures[id] == "context_item" then
      local context = get_node_text(node, chat.bufnr)
      -- Clean both icons
      context = vim.iter(vim.tbl_values(icons)):fold(select(1, context:gsub("^> %- ", "")), function(acc, icon)
        return select(1, acc:gsub(icon, ""))
      end)
      table.insert(items, vim.trim(context))
    end
  end

  return items
end

return Context
