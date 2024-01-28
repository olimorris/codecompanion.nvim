--Taken from https://github.com/jackMort/ChatGPT.nvim/blob/main/lua/chatgpt/flows/chat/tokens.lua

local M = {}

---@param message string The text to calculate the number of tokens for.
local function calculate_tokens(message)
  local tokens = 0

  local current_token = ""

  if message == "" or string.sub(message, 1, 2) == "# " then
    return tokens
  end

  for char in message:gmatch(".") do
    if char == " " or char == "\n" then
      if current_token ~= "" then
        tokens = tokens + 1
        current_token = ""
      end
    else
      current_token = current_token .. char
    end
  end

  if current_token ~= "" then
    tokens = tokens + 1
  end

  return tokens
end

---@param messages table The messages to calculate the number of tokens for.
function M.get_tokens(messages)
  local tokens = 0

  for _, message in ipairs(messages) do
    tokens = tokens + calculate_tokens(message.content)
  end

  return tokens
end

local function get_messages(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local query_str = [[
    (section) @section
  ]]

  local parser = vim.treesitter.get_parser(bufnr, "markdown", {})
  local tree = parser:parse()[1] -- Assuming there's only one syntax tree
  local query = vim.treesitter.query.parse("markdown", query_str)

  local messages = {}
  for pattern, match in query:iter_matches(tree:root(), bufnr) do
    if query.captures[pattern] == "section" then
      local section_node = match[pattern]
      local section_start_row, _, section_end_row, _ = section_node:range()
      local lines = vim.api.nvim_buf_get_lines(bufnr, section_start_row, section_end_row + 1, false)
      for id, _ in ipairs(match) do
        if query.captures[id] ~= "heading" then
          table.insert(messages, lines)
        end
      end
    end
  end

  return messages
end

---@param bufnr nil|number
function M.display_tokens(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ns_id = vim.api.nvim_create_namespace("CodeCompanionTokens")

  local parser = vim.treesitter.get_parser(bufnr, "markdown", {})
  local tree = parser:parse()[1]

  local query = vim.treesitter.query.parse("markdown", "(atx_heading) @heading")
  local last_heading_node = nil
  for id, node, _ in query:iter_captures(tree:root(), bufnr) do
    if query.captures[id] == "heading" then
      last_heading_node = node
    end
  end

  if last_heading_node then
    local _, _, end_row, _ = last_heading_node:range()

    local tokens = 0
    for _, messages in ipairs(get_messages(bufnr)) do
      for _, message in ipairs(messages) do
        tokens = tokens + calculate_tokens(message)
      end
    end

    local virtual_text = { { " (" .. tokens .. " tokens)", "CodeCompanionTokens" } }

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, end_row - 1, 0, {
      virt_text = virtual_text,
      virt_text_pos = "eol", -- 'overlay' or 'right_align' or 'eol'
    })
  end
end

return M
