--=============================================================================
-- Functions for parsing a chat buffer using Tree-sitter
--=============================================================================
local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.helpers")
local log = require("codecompanion.utils.log")
local yaml = require("codecompanion.utils.yaml")

local get_node_text = vim.treesitter.get_node_text --[[@type function]]
local get_query = vim.treesitter.query.get --[[@type function]]

local cached_markdown_chat_query
local function markdown_chat_query()
  cached_markdown_chat_query = cached_markdown_chat_query or get_query("markdown", "chat")
  return cached_markdown_chat_query
end

local cached_yaml_chat_query
local function yaml_chat_query()
  cached_yaml_chat_query = cached_yaml_chat_query or get_query("yaml", "chat")
  return cached_yaml_chat_query
end

local cached_image_query
local function image_query()
  cached_image_query = cached_image_query
    or vim.treesitter.query.parse(
      "markdown_inline",
      [[((image) @image)
    ((inline_link) @link)]]
    )
  return cached_image_query
end

local M = {}

---Parse the chat buffer for settings
---@param bufnr number
---@param parser vim.treesitter.LanguageTree
---@param adapter? CodeCompanion.HTTPAdapter
---@return table
function M.settings(bufnr, parser, adapter)
  local settings = {}

  local query = yaml_chat_query()
  local root = parser:parse()[1]:root()

  local end_line = -1
  if adapter then
    -- Account for the two YAML lines and the fact Tree-sitter is 0-indexed
    end_line = vim.tbl_count(adapter.schema) + 2 - 1
  end

  for _, matches, _ in query:iter_matches(root, bufnr, 0, end_line) do
    local nodes = matches[1]
    local node = type(nodes) == "table" and nodes[1] or nodes

    local value = get_node_text(node, bufnr)

    settings = yaml.decode(value)
    break
  end

  if not settings then
    log:error("[chat::parser] Failed to parse settings in chat buffer")
    return {}
  end

  return settings
end

---Get the settings key at the current cursor position
---@param chat CodeCompanion.Chat
---@param opts? table
function M.get_settings_key(chat, opts)
  opts = vim.tbl_extend("force", opts or {}, {
    lang = "yaml",
    ignore_injections = false,
  })
  local node = vim.treesitter.get_node(opts)
  while node and node:type() ~= "block_mapping_pair" do
    node = node:parent()
  end
  if not node then
    return
  end
  local key_node = node:named_child(0)
  local key_name = get_node_text(key_node, chat.bufnr)
  return key_name, node
end

---Chat buffers already warned about, so a malformed transcript is reported once
---rather than on every submit. The offending fence stays broken for the rest of
---the conversation -- the transcript is a record and is never rewritten -- so the
---fallback below keeps firing for as long as the chat lives. Buffer numbers are
---not reused within a session, so this never suppresses a different buffer.
local warned_buffers = {}

---Recover the user's message by reading the buffer, when Tree-sitter cannot
---
---`queries/markdown/chat.scm` finds the message by walking Markdown sections, so
---an unbalanced code fence anywhere above the user header makes the parser
---swallow that header. The query then matches no user section and, because
---`helpers.has_user_messages()` is true mid-conversation, the text the user just
---typed is dropped silently on submit. Any producer of chat text can leave a
---fence open, including an LLM response truncated mid-block by `max_tokens`.
---
---This runs only when the query yielded nothing, and it does not re-parse.
---`start_range` is `chat.header_line`, the 1-based row of the user header, so the
---message is everything below that row: the position comes from the builder's own
---bookkeeping rather than from a tree already known to be wrong, which is what
---makes reading raw lines trustworthy here.
---@param chat CodeCompanion.Chat
---@param start_range number The 1-based row of the user header
---@return { content: string }|nil
local function recover_messages(chat, start_range)
  -- `start_range - 1` is the header row 0-indexed, so `start_range` is the row below it
  local lines = vim.api.nvim_buf_get_lines(chat.bufnr, start_range, -1, false)

  -- The row below a header is blank, and `strip_context` only strips *leading*
  -- entries, so the context block has to be flushed to the front to be seen. The
  -- Tree-sitter path never meets this: it is handed section text, not raw lines.
  while lines[1] and vim.trim(lines[1]) == "" do
    table.remove(lines, 1)
  end
  lines = helpers.strip_context(lines)
  local content = vim.trim(table.concat(lines, "\n"))

  -- An empty section must stay empty: tools auto-submit with no user message, and
  -- inventing one here would send a phantom prompt.
  if content == "" then
    return nil
  end

  if not warned_buffers[chat.bufnr] then
    warned_buffers[chat.bufnr] = true
    log:warn(
      "[chat::parser] Tree-sitter found no user message, so it was read from the buffer instead. "
        .. "An unterminated code fence above the last user header is the usual cause."
    )
  end
  log:debug("[chat::parser] Recovered %d line(s) of user message from row %d", #lines, start_range)

  return { content = content }
end

---Parse the chat buffer for the last message
---@param chat CodeCompanion.Chat
---@param start_range number
---@return { content: string }|nil
function M.messages(chat, start_range)
  local query = markdown_chat_query()

  local tree = chat.parsers.markdown:parse({ start_range - 1, -1 })[1]
  local root = tree:root()

  local content = {}
  local last_role = nil

  for id, node in query:iter_captures(root, chat.bufnr, start_range - 1, -1) do
    if query.captures[id] == "role" then
      last_role = helpers.format_role(get_node_text(node, chat.bufnr))
    elseif last_role == config.interactions.chat.roles.user and query.captures[id] == "content" then
      table.insert(content, get_node_text(node, chat.bufnr))
    end
  end

  content = helpers.strip_context(content) -- If users send a blank message to the LLM, sometimes context is included
  if not vim.tbl_isempty(content) then
    return { content = vim.trim(table.concat(content, "\n\n")) }
  end

  return recover_messages(chat, start_range)
end

---Is `row` inside a fenced code block that was never closed?
---
---A closed block has two `fenced_code_block_delimiter` children; an unterminated
---one has a single opening delimiter and runs to the end of the buffer. Only such
---a block can hide a header from `queries/markdown/chat.scm` unintentionally, so
---this is the one situation in which the scan below may overrule Tree-sitter: a
---heading inside a *closed* block is there because its author put it there, and
---must go on being treated as code.
---@param root TSNode The root of the tree `M.headers` has already parsed
---@param row number 0-indexed
---@return boolean
local function hidden_by_open_fence(root, row)
  local node = root:descendant_for_range(row, 0, row, 0)
  while node do
    if node:type() == "fenced_code_block" then
      local delimiters = 0
      for child in node:iter_children() do
        if child:type() == "fenced_code_block_delimiter" then
          delimiters = delimiters + 1
        end
      end
      return delimiters < 2
    end
    node = node:parent()
  end
  return false
end

---Find a user header that an unclosed code fence hid from Tree-sitter
---
---`M.headers` seeds `chat.header_line` for restored chats, and on a malformed
---buffer it does not fail cleanly: it returns the last header it can still *see*,
---which is an earlier one. Everything downstream then parses from that row, so
---`M.messages` finds a previous message and returns it -- worse than returning
---nothing, because the fallback above sees content and never fires, and the user's
---new prompt is replaced by an old one.
---
---Only rows below `after` are considered, so a header Tree-sitter did find is
---never traded for an earlier one, and every candidate must be provably hidden by
---an unclosed fence.
---@param chat CodeCompanion.Chat
---@param root TSNode The root of the tree `M.headers` has already parsed
---@param after number The 0-indexed row Tree-sitter reported, or -1 if it found none
---@return number|nil The 0-indexed row of the header, in the rows Tree-sitter reports
local function recover_headers(chat, root, after)
  local lines = vim.api.nvim_buf_get_lines(chat.bufnr, after + 1, -1, false)
  for i = #lines, 1, -1 do
    local heading = lines[i]:match("^##%s+(.-)%s*$")
    if heading and helpers.format_role(heading) == config.interactions.chat.roles.user then
      local row = after + i
      if hidden_by_open_fence(root, row) then
        return row
      end
    end
  end
end

---Parse the chat buffer for the last header
---@param chat CodeCompanion.Chat
---@return number|nil
function M.headers(chat)
  local query = markdown_chat_query()

  local tree = chat.parsers.markdown:parse({ 0, -1 })[1]
  local root = tree:root()

  local last_match = nil
  for id, node in query:iter_captures(root, chat.bufnr) do
    if query.captures[id] == "role_only" then
      local role = helpers.format_role(get_node_text(node, chat.bufnr))
      if role == config.interactions.chat.roles.user then
        last_match = node
      end
    end
  end

  -- Tree-sitter stays authoritative unless an unclosed fence hid a later header
  -- from it. When nothing is recovered its own result is returned untouched.
  local recovered = recover_headers(chat, root, last_match and last_match:range() or -1)
  if recovered then
    return recovered
  end

  if last_match then
    return last_match:range()
  end
end

---Parse a section of the buffer for Markdown images.
---@param chat CodeCompanion.Chat The chat instance.
---@param start_range number The 1-indexed line number from where to start parsing.
function M.images(chat, start_range)
  local ts_query = image_query()
  local parser = chat.parsers.markdown_inline or vim.treesitter.get_parser(chat.bufnr, "markdown_inline")

  local tree = parser:parse({ start_range, -1 })[1]
  local root = tree:root()

  local links = {}

  for id, node in ts_query:iter_captures(root, chat.bufnr, start_range - 1, -1) do
    local capture_name = ts_query.captures[id]
    if capture_name == "image" or capture_name == "link" then
      local link_label_text = nil
      local link_dest_text = nil

      for child in node:iter_children() do
        local child_type = child:type()

        if child_type == "link_text" or child_type == "image_description" then
          local text = get_node_text(child, chat.bufnr)
          link_label_text = text
        elseif child_type == "link_destination" then
          local text = get_node_text(child, chat.bufnr)
          link_dest_text = text
        end
      end

      if link_dest_text and (capture_name == "image" or link_label_text == "Image") then
        table.insert(links, { text = link_label_text, path = link_dest_text })
      end
    end
  end

  if vim.tbl_isempty(links) then
    return nil
  end

  return links
end

---Parse the chat buffer for a code block
---returns the code block that the cursor is in or the last code block
---@param chat CodeCompanion.Chat
---@param cursor? table
---@return TSNode|nil
function M.codeblock(chat, cursor)
  local root = chat.parsers.markdown:parse()[1]:root()
  local query = markdown_chat_query()
  if query == nil then
    return nil
  end

  local last_match = nil
  for id, node in query:iter_captures(root, chat.bufnr, 0, -1) do
    if query.captures[id] == "code" then
      if cursor then
        local start_row, start_col, end_row, end_col = node:range()
        if cursor[1] >= start_row and cursor[1] <= end_row and cursor[2] >= start_col and cursor[2] <= end_col then
          return node
        end
      end
      last_match = node
    end
  end

  return last_match
end

return M
