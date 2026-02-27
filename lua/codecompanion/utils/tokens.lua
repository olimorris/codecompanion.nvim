local api = vim.api

local M = {}

local DEFAULTS = {
  alpha_chars_per_token = 6,
  other_bytes_per_token = 3,
  message_overhead = 0,
}

---Calculate the number of tokens in a message (lightweight heuristic).
---Inspired by https://github.com/johannschopplich/tokenx
---@param message string
---@param opts? table
---@return number
function M.calculate(message, opts)
  if type(message) ~= "string" or message == "" then
    return 0
  end

  local alpha_chars_per_token = (opts and opts.alpha_chars_per_token) or DEFAULTS.alpha_chars_per_token
  local other_bytes_per_token = (opts and opts.other_bytes_per_token) or DEFAULTS.other_bytes_per_token

  local tokens = 0
  local i = 1
  local len = #message

  while i <= len do
    local b = message:byte(i)

    if not b then
      break
    end

    if b < 128 then
      -- whitespace run → 0 tokens
      if b == 32 or b == 9 or b == 10 or b == 13 or b == 11 or b == 12 then
        i = i + 1
        while i <= len do
          local c = message:byte(i)
          if not c or not (c == 32 or c == 9 or c == 10 or c == 13 or c == 11 or c == 12) then
            break
          end
          i = i + 1
        end
      -- alpha run [A-Za-z] or alphanumeric run [A-Za-z0-9]
      elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) then
        local j = i + 1
        while j <= len do
          local c = message:byte(j)
          if not c or not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57)) then
            break
          end
          j = j + 1
        end
        local run_len = j - i
        -- numeric-only run or short segment → 1 token
        local is_numeric = true
        for k = i, j - 1 do
          local c = message:byte(k)
          if not (c >= 48 and c <= 57) then
            is_numeric = false
            break
          end
        end
        if is_numeric or run_len <= 3 then
          tokens = tokens + 1
        else
          tokens = tokens + math.ceil(run_len / alpha_chars_per_token)
        end
        i = j
      else
        -- ASCII punctuation/symbol run
        local j = i + 1
        while j <= len do
          local c = message:byte(j)
          if not c or c < 33 or c > 126 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) then
            break
          end
          j = j + 1
        end
        local run_len = j - i
        tokens = tokens + math.ceil(run_len / 2)
        i = j
      end
    else
      -- Non-ASCII: consume the full multi-byte sequence(s)
      local j = i + 1
      while j <= len do
        local c = message:byte(j)
        if not c or c < 128 then
          break
        end
        j = j + 1
      end
      tokens = tokens + math.ceil((j - i) / other_bytes_per_token)
      i = j
    end
  end

  return tokens
end

---Get the total number of tokens in a list of messages.
---@param messages table
---@param opts? table
---@return number
function M.get_tokens(messages, opts)
  local message_overhead = DEFAULTS.message_overhead
  if opts and opts.message_overhead then
    message_overhead = opts.message_overhead
  end

  local tokens = 0
  for _, message in ipairs(messages or {}) do
    local content = type(message) == "table" and message.content or message
    if type(content) == "string" and content ~= "" then
      tokens = tokens + M.calculate(content, opts) + message_overhead
    end
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
