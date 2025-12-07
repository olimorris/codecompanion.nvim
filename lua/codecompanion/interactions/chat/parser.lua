--=============================================================================
-- Functions for parsing a chat buffer using Tree-sitter
--=============================================================================
local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.helpers")
local log = require("codecompanion.utils.log")
local yaml = require("codecompanion.utils.yaml")

local get_node_text = vim.treesitter.get_node_text --[[@type function]]
local get_query = vim.treesitter.query.get --[[@type function]]

local M = {}

---Parse the chat buffer for settings
---@param bufnr number
---@param parser vim.treesitter.LanguageTree
---@param adapter? CodeCompanion.HTTPAdapter
---@return table
function M.settings(bufnr, parser, adapter)
  local settings = {}

  local query = get_query("yaml", "chat")
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

---Parse the chat buffer for the last message
---@param chat CodeCompanion.Chat
---@param start_range number
---@return { content: string }|nil
function M.messages(chat, start_range)
  local query = get_query("markdown", "chat")

  local tree = chat.chat_parser:parse({ start_range - 1, -1 })[1]
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

  return nil
end

---Parse the chat buffer for the last header
---@param chat CodeCompanion.Chat
---@return number|nil
function M.headers(chat)
  local query = get_query("markdown", "chat")

  local tree = chat.chat_parser:parse({ 0, -1 })[1]
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

  if last_match then
    return last_match:range()
  end
end

---Parse a section of the buffer for Markdown inline links.
---@param chat CodeCompanion.Chat The chat instance.
---@param start_range number The 1-indexed line number from where to start parsing.
function M.images(chat, start_range)
  local ts_query = vim.treesitter.query.parse(
    "markdown_inline",
    [[
((inline_link) @link)
  ]]
  )
  local parser = vim.treesitter.get_parser(chat.bufnr, "markdown_inline")

  local tree = parser:parse({ start_range, -1 })[1]
  local root = tree:root()

  local links = {}

  for id, node in ts_query:iter_captures(root, chat.bufnr, start_range - 1, -1) do
    local capture_name = ts_query.captures[id]
    if capture_name == "link" then
      local link_label_text = nil
      local link_dest_text = nil

      for child in node:iter_children() do
        local child_type = child:type()

        if child_type == "link_text" then
          local text = get_node_text(child, chat.bufnr)
          link_label_text = text
        elseif child_type == "link_destination" then
          local text = get_node_text(child, chat.bufnr)
          link_dest_text = text
        end
      end

      if link_label_text and link_dest_text then
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
  local root = chat.chat_parser:parse()[1]:root()
  local query = get_query("markdown", "chat")
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
