--Taken from https://github.com/jackMort/ChatGPT.nvim/blob/main/lua/chatgpt/flows/chat/tokens.lua
local api = vim.api

local M = {}

---Calculate the number of tokens in a message
---@param message string The text to calculate the number of tokens for
---@return number The number of tokens in the message
function M.calculate(message)
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
---@return number The number of tokens in the messages.
function M.get_tokens(messages)
  local tokens = 0

  for _, message in ipairs(messages) do
    tokens = tokens + M.calculate(message.content)
  end

  return tokens
end

---Display the number of tokens in the current buffer
---@param tokens number
---@param bufnr? number
---@return nil
function M.display(tokens, bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local ns_id = api.nvim_create_namespace("CodeCompanionTokens")
  api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

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

    local virtual_text = { { " (" .. tokens .. " tokens) ", "CodeCompanionChatTokens" } }

    api.nvim_buf_set_extmark(bufnr, ns_id, end_row - 1, 0, {
      virt_text = virtual_text,
      virt_text_pos = "eol", -- 'overlay' or 'right_align' or 'eol'
    })
  end
end

return M
