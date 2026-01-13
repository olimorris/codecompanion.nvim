local M = {}

---@type number?
M._scratch_buf = nil

---Prepend a marker to each virtual line
---@param vl CodeCompanion.Text[]
---@param marker string
---@param hl_group string
---@return CodeCompanion.Text[]
function M.prepend_marker(vl, marker, hl_group)
  local result = {}
  for _, vt in ipairs(vl) do
    local new_vt = { { marker .. " ", hl_group } }
    for _, segment in ipairs(vt) do
      table.insert(new_vt, segment)
    end
    table.insert(result, new_vt)
  end
  return result
end

---Split a string into words and non-words with position tracking. UTF-8 aware
---@param str string
---@return { word: string, start_col: number, end_col: number }[]
function M.split_words(str)
  if str == "" then
    return {}
  end

  local ret = {} ---@type { word: string, start_col: number, end_col: number }[]
  local word_chars = {} ---@type string[]
  local word_start = nil ---@type number?
  local starts = vim.str_utf_pos(str)

  local function flush(pos)
    if #word_chars > 0 and word_start then
      ret[#ret + 1] = {
        word = table.concat(word_chars),
        start_col = word_start,
        end_col = pos,
      }
      word_chars = {}
      word_start = nil
    end
  end

  for idx, start in ipairs(starts) do
    local stop = (starts[idx + 1] or (#str + 1)) - 1
    local ch = str:sub(start, stop)
    if vim.fn.charclass(ch) == 2 then -- iskeyword
      if not word_start then
        word_start = start - 1
      end
      word_chars[#word_chars + 1] = ch
    else
      flush(start - 1)
      ret[#ret + 1] = {
        word = ch,
        start_col = start - 1,
        end_col = stop,
      }
    end
  end

  flush(#str)
  return ret
end

return M
