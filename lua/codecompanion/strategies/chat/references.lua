--[[
Handle the references that are shared with the chat buffer from sources such as
Slash Commands or variables. References are displayed back to the user via
the chat buffer, using block quotes and lists.
--]]
local config = require("codecompanion.config")
local helpers = require("codecompanion.strategies.chat.helpers")

local api = vim.api
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

---Parse the chat buffer to find where to add the references
---@param chat CodeCompanion.Chat
---@return table|nil
local function ts_parse_buffer(chat)
  local query = vim.treesitter.query.get("markdown", "reference")

  local tree = chat.parser:parse({ chat.header_line - 1, -1 })[1]
  local root = tree:root()

  -- Check if there are any references already in the chat buffer
  local refs
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "refs" then
      refs = node
    end
  end

  if refs and not vim.tbl_isempty(chat.refs) then
    local start_row, _, end_row, _ = refs:range()
    return {
      capture = "refs",
      start_row = start_row + 2,
      end_row = end_row + 1,
    }
  end

  -- If not, check if there is a heading to add the references below
  local role
  local role_node
  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = vim.treesitter.get_node_text(node, chat.bufnr)
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

---Add a reference to the chat buffer
---@param chat CodeCompanion.Chat
---@param ref CodeCompanion.Chat.Ref
---@param row integer
local function add(chat, ref, row)
  if not ref.opts.visible then
    return
  end
  local lines = {}

  -- Check if this reference has special options and format accordingly
  local ref_text
  if ref.opts and ref.opts.pinned then
    ref_text = string.format("> - %s%s", icons.pinned, ref.id)
  elseif ref.opts and ref.opts.watched then
    ref_text = string.format("> - %s%s", icons.watched, ref.id)
  else
    ref_text = string.format("> - %s", ref.id)
  end

  table.insert(lines, ref_text)

  if vim.tbl_count(chat.refs) == 1 then
    table.insert(lines, 1, "> Context:")
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

---@class CodeCompanion.Chat.References
---@field Chat CodeCompanion.Chat
local References = {}

---@class CodeCompanion.Chat.RefsArgs
---@field chat CodeCompanion.Chat

---@param args CodeCompanion.Chat.RefsArgs
function References.new(args)
  local self = setmetatable({
    Chat = args.chat,
  }, { __index = References })

  return self
end

---Add a reference to the chat buffer
---@param ref CodeCompanion.Chat.Ref
---@return nil
function References:add(ref)
  if not ref or not config.display.chat.show_references then
    return self
  end

  if ref then
    if not ref.opts then
      ref.opts = {}
    end

    -- Ensure both properties exist with defaults
    ref.opts.pinned = ref.opts.pinned or false
    ref.opts.watched = ref.opts.watched or false
    ref.opts.visible = ref.opts.visible

    if ref.opts.visible == nil then
      ref.opts.visible = config.display.chat.show_references
    end
    table.insert(self.Chat.refs, ref)
    -- If it's a buffer reference and it's being watched, start watching
    if ref.bufnr and ref.opts.watched then
      self.Chat.watchers:watch(ref.bufnr)
    end
  end

  local parsed_buffer = ts_parse_buffer(self.Chat)

  if parsed_buffer then
    -- If the reference block already exists, add to it
    if parsed_buffer.capture == "refs" then
      add(self.Chat, ref, parsed_buffer.end_row - 1)
    -- If there are no references then add a new block below the heading
    elseif parsed_buffer.capture == "role" then
      add(self.Chat, ref, parsed_buffer.end_row + 1)
    end
  end
end

---Clear any references from a message in the chat buffer to remove unnecessary
---context before it's sent to the LLM.
---@param message table
---@return table
function References:clear(message)
  if vim.tbl_isempty(self.Chat.refs) or not config.display.chat.show_references then
    return message or nil
  end

  local parser = vim.treesitter.get_string_parser(message.content, "markdown")
  local query = vim.treesitter.query.get("markdown", "reference")
  local root = parser:parse()[1]:root()

  local refs = nil
  for id, node in query:iter_captures(root, message.content) do
    if query.captures[id] == "refs" then
      refs = node
    end
  end

  if refs then
    local start_row, _, end_row, _ = refs:range()
    message.content = vim.split(message.content, "\n")
    for i = start_row, end_row do
      message.content[i] = ""
    end
    message.content = vim.trim(table.concat(message.content, "\n"))
  end

  return message
end

---Render all the references in the chat buffer after a response from the LLM
---@return nil
function References:render()
  local chat = self.Chat
  if vim.tbl_isempty(chat.refs) then
    return self
  end
  local start_row = chat.header_line + 1

  local lines = {}
  table.insert(lines, "> Context:")

  for _, ref in pairs(chat.refs) do
    if not ref or (ref.opts and ref.opts.visible == false) then
      goto continue
    end
    if ref.opts and ref.opts.pinned then
      table.insert(lines, string.format("> - %s%s", icons.pinned, ref.id))
    elseif ref.opts and ref.opts.watched then
      table.insert(lines, string.format("> - %s%s", icons.watched, ref.id))
    else
      table.insert(lines, string.format("> - %s", ref.id))
    end
    ::continue::
  end
  if #lines == 1 then
    -- no ref added
    return
  end
  table.insert(lines, "")

  return api.nvim_buf_set_lines(chat.bufnr, start_row, start_row, false, lines)
end

---Make a unique ID from the buffer number
---@param bufnr number
---@return string
function References:make_id_from_buf(bufnr)
  local bufname = api.nvim_buf_get_name(bufnr)
  return vim.fn.fnamemodify(bufname, ":.")
end

---Determine if a reference can be pinned
---@param ref string
---@return boolean
function References:can_be_pinned(ref)
  for _, pin in ipairs(allowed_pins) do
    if ref:find(pin) then
      return true
    end
  end
  return false
end

---Determine if a reference can be watched
---@param ref string
---@return boolean
function References:can_be_watched(ref)
  for _, watch in ipairs(allowed_watchers) do
    if ref:find(watch) then
      return true
    end
  end
  return false
end

---Get the references from the chat buffer
---@return table
function References:get_from_chat()
  local query = vim.treesitter.query.get("markdown", "reference")

  local tree = self.Chat.parser:parse()[1]
  local root = tree:root()

  local refs = {}
  local role = nil

  local chat = self.Chat

  for id, node in query:iter_captures(root, chat.bufnr, chat.header_line - 1, -1) do
    if query.captures[id] == "role" then
      role = helpers.format_role(vim.treesitter.get_node_text(node, chat.bufnr))
    elseif role == user_role and query.captures[id] == "ref" then
      local ref = vim.treesitter.get_node_text(node, chat.bufnr)
      -- Clean both pinned and watched icons
      ref = vim.iter(vim.tbl_values(icons)):fold(select(1, ref:gsub("^> %- ", "")), function(acc, icon)
        return select(1, acc:gsub(icon, ""))
      end)
      table.insert(refs, vim.trim(ref))
    end
  end

  return refs
end

return References
