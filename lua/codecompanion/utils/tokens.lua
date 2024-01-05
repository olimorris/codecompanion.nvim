--Taken from https://github.com/jackMort/ChatGPT.nvim/blob/main/lua/chatgpt/flows/chat/tokens.lua

local M = {}

---@param message string The text to calculate the number of tokens for.
local function calculate_tokens(message)
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
function M.get_tokens(messages)
  local tokens = 0

  for _, message in ipairs(messages) do
    tokens = tokens + calculate_tokens(message.content)
  end

  return tokens
end

return M
