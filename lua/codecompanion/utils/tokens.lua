--Taken from https://github.com/jackMort/ChatGPT.nvim/blob/main/lua/chatgpt/flows/chat/tokens.lua
local api = vim.api

local M = {}

---Calculate the number of tokens in a message
---@param message table The messages table
---@return number The number of tokens in the message
function M.calculate(message)
  local tokens = 0
  local current_token = ""

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
---@param token_str string
---@param ns_id number
---@param parser table
---@param start_row number
---@param bufnr? number
---@return nil
function M.display(token_str, ns_id, parser, start_row, bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local query = vim.treesitter.query.get("markdown", "tokens")
  local tree = parser:parse({ start_row - 1, -1 })[1]
  local root = tree:root()

  local header
  for id, node in query:iter_captures(root, bufnr, start_row - 1, -1) do
    if query.captures[id] == "role" then
      header = node
    end
  end

  if header then
    local _, _, end_row, _ = header:range()

    local virtual_text = { { token_str, "CodeCompanionChatTokens" } }

    api.nvim_buf_set_extmark(bufnr, ns_id, end_row - 1, 0, {
      virt_text = virtual_text,
      virt_text_pos = "eol",
      priority = 110,
      hl_mode = "combine",
    })
  end
end

return M
