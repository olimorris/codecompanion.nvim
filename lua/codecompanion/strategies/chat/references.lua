--[[
Handle the references that are shared with the chat buffer from sources such as
Slash Commands or variables. References are displayed back to the user via
the chat buffer, using block quotes and lists.
--]]
local config = require("codecompanion.config")

local api = vim.api
local user_role = config.strategies.chat.roles.user

---Parse the chat buffer to find where to add the references
---@param chat CodeCompanion.Chat
---@return table|nil
local function ts_parse_buffer(chat)
  local parser = vim.treesitter.get_parser(chat.bufnr, "markdown")
  local query = vim.treesitter.query.parse(
    "markdown",
    string.format(
      [[(
  (section
    (atx_heading) @heading
    (#match? @heading "## %s")
  (block_quote)? @refs
  )
)]],
      user_role
    )
  )

  local root = parser:parse()[1]:root()

  local refs = nil
  for id, node in query:iter_captures(root, chat.bufnr, 0, -1) do
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

  local heading = nil
  for id, node in query:iter_captures(root, chat.bufnr, 0, -1) do
    if query.captures[id] == "heading" then
      heading = node
    end
  end

  if heading then
    local start_row, _, end_row, _ = heading:range()
    return {
      capture = "heading",
      start_row = start_row + 1,
      end_row = end_row + 1,
    }
  end

  return nil
end

---Add a reference to the chat buffer
---@param row integer
local function add(chat, ref, row)
  local lines = {}

  table.insert(lines, string.format("> - %s", ref.id))

  if vim.tbl_count(chat.refs) == 1 then
    table.insert(lines, 1, "> Sharing:")
    table.insert(lines, "")
  end

  api.nvim_buf_set_lines(chat.bufnr, row, row, false, lines)
end

---@class CodeCompanion.Chat.References
---@field chat CodeCompanion.Chat
---@field refs table<CodeCompanion.Chat.Ref>
local References = {}

---@class CodeCompanion.Chat.RefsArgs
---@field chat CodeCompanion.Chat
---@field refs table<CodeCompanion.Chat.Ref>

---@param chat CodeCompanion.Chat
function References.new(chat)
  local self = setmetatable({
    chat = chat,
  }, { __index = References })

  return self
end

---Add a reference to the chat buffer
---@param ref CodeCompanion.Chat.Ref
---@return CodeCompanion.Chat.References
function References:add(ref)
  if not ref or not config.display.chat.show_references then
    return self
  end

  if ref then
    table.insert(self.chat.refs, ref)
  end

  local parsed_buffer = ts_parse_buffer(self.chat)

  if parsed_buffer then
    -- If the reference block already exists, add to it
    if parsed_buffer.capture == "refs" then
      add(self.chat, ref, parsed_buffer.end_row - 1)
    -- If there are no references then add a new block below the heading
    elseif parsed_buffer.capture == "heading" then
      add(self.chat, ref, parsed_buffer.end_row)
    end
    return self
  end

  return self
end

---Clear any references from a message in the chat buffer to remove unnecessary
---context before it's sent to the LLM.
---@param message table
---@return table
function References:clear(message)
  if vim.tbl_isempty(self.chat.refs) or not config.display.chat.show_references then
    return message or nil
  end

  local parser = vim.treesitter.get_string_parser(message.content, "markdown")
  local query = vim.treesitter.query.get("markdown", "chat")
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
---@return CodeCompanion.Chat.References
function References:render()
  if vim.tbl_isempty(self.chat.refs) then
    return self
  end

  local parser = vim.treesitter.get_parser(self.chat.bufnr, "markdown")
  local query = vim.treesitter.query.parse(
    "markdown",
    string.format(
      [[(
  (section
    (atx_heading) @heading
    (#match? @heading "## %s")
  )
)]],
      user_role
    )
  )
  local root = parser:parse()[1]:root()

  local heading = nil
  for id, node in query:iter_captures(root, self.chat.bufnr, 0, -1) do
    if query.captures[id] == "heading" then
      heading = node
    end
  end

  if heading then
    local start_row, _, _, _ = heading:range()
    start_row = start_row + 2

    local lines = {}
    table.insert(lines, "> Sharing:")

    for _, ref in ipairs(self.chat.refs) do
      table.insert(lines, string.format("> - %s", ref.id))
    end
    table.insert(lines, "")

    api.nvim_buf_set_lines(self.chat.bufnr, start_row, start_row, false, lines)
  end

  return self
end

---Make a unique ID from the buffer number
---@param bufnr number
---@return string
function References:make_id_from_buf(bufnr)
  local bufname = api.nvim_buf_get_name(bufnr)
  return vim.fn.fnamemodify(bufname, ":.")
end

return References
