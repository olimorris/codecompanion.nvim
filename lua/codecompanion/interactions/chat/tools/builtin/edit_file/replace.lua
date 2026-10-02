local fmt = string.format

local M = {}

local CURLY_QUOTES = { ["‘"] = "'", ["’"] = "'", ["“"] = '"', ["”"] = '"' }
local CURLY_QUOTE_PATTERN = "\226\128[\152\153\156\157]"
local EM_DASH = "\226\128\148"
local EN_DASH = "\226\128\147"
local LETTER = "[%a\128-\255]"

---@param text string
---@return string
local function normalize_quotes(text)
  return (text:gsub(CURLY_QUOTE_PATTERN, CURLY_QUOTES))
end

---Return the start position of every non-overlapping match
---@param content string
---@param search string
---@return number[]
local function find_all(content, search)
  local positions = {}
  local from = 1
  while true do
    local start = content:find(search, from, true)
    if not start then
      return positions
    end
    table.insert(positions, start)
    from = start + #search
  end
end

---Convert a position in the quote-normalized content to the same character's position in the original
---@param content string
---@param normalized_position number
---@return number
local function get_original_position(content, normalized_position)
  local shift = 0
  for quote_start in content:gmatch("()" .. CURLY_QUOTE_PATTERN) do
    if quote_start - shift >= normalized_position then
      break
    end
    -- A curly quote is 3 bytes but normalizes to 1, pushing every later position back by 2
    shift = shift + 2
  end
  return normalized_position + shift
end

---Find the text in the content that matches the search once curly quotes are straightened
---@param content string
---@param search string
---@return string|nil
local function find_with_straight_quotes(content, search)
  local normalized_search = normalize_quotes(search)
  local normalized_start = normalize_quotes(content):find(normalized_search, 1, true)
  if not normalized_start then
    return nil
  end

  local start = get_original_position(content, normalized_start)
  local finish = get_original_position(content, normalized_start + #normalized_search)
  return content:sub(start, finish - 1)
end

---@param text string
---@param position number
---@return boolean
local function is_opening_quote(text, position)
  if position == 1 then
    return true
  end
  local preceding = text:sub(position - 3, position - 1)
  return text:sub(position - 1, position - 1):match("[%s%(%[{]") ~= nil or preceding == EM_DASH or preceding == EN_DASH
end

---Curl the straight quotes in the text to match the curly quotes in the file
---@param text string
---@param matched string
---@return string
local function apply_quote_style(text, matched)
  local has_curly_double = matched:find("“", 1, true) or matched:find("”", 1, true)
  local has_curly_single = matched:find("‘", 1, true) or matched:find("’", 1, true)

  return (
    text:gsub("()(['\"])", function(position, quote)
      if quote == '"' and has_curly_double then
        return is_opening_quote(text, position) and "“" or "”"
      end
      if quote == "'" and has_curly_single then
        local is_apostrophe = text:sub(position - 1, position - 1):match(LETTER)
          and text:sub(position + 1, position + 1):match(LETTER)
        return (not is_apostrophe and is_opening_quote(text, position)) and "‘" or "’"
      end
    end)
  )
end

---@param content string
---@param position number
---@return boolean
local function is_line_start(content, position)
  return position == 1 or content:sub(position - 1, position - 1) == "\n"
end

---Replace each match, consuming the trailing newline when whole lines are deleted
---@param content string
---@param opts { search: string, replacement: string, positions: number[] }
---@return string
local function splice(content, opts)
  local deletes_lines = opts.replacement == "" and opts.search:sub(-1) ~= "\n"
  local parts = {}
  local cursor = 1

  for _, start in ipairs(opts.positions) do
    local finish = start + #opts.search
    if deletes_lines and is_line_start(content, start) and content:sub(finish, finish) == "\n" then
      finish = finish + 1
    end
    table.insert(parts, content:sub(cursor, start - 1))
    table.insert(parts, opts.replacement)
    cursor = finish
  end
  table.insert(parts, content:sub(cursor))

  return table.concat(parts)
end

---Replace `old_string` with `new_string` in content that uses LF line endings
---@param content string
---@param opts { old_string: string, new_string: string, replace_all?: boolean }
---@return { content?: string, error?: string }
function M.apply(content, opts)
  local old_string = opts.old_string:gsub("\r\n", "\n")
  local new_string = opts.new_string:gsub("\r\n", "\n")

  if old_string == "" then
    if content == "" then
      return { content = new_string }
    end

    return { error = "`old_string` is empty. Include the existing text you want to replace" }
  end

  if old_string == new_string then
    return { error = "`old_string` and `new_string` are identical, so there is nothing to change" }
  end

  local search = old_string
  if not content:find(search, 1, true) then
    search = find_with_straight_quotes(content, old_string)
    if not search then
      return {
        error = "`old_string` was not found in the file. It must match the file exactly, including whitespace and indentation",
      }
    end
    new_string = apply_quote_style(new_string, search)
  end

  local positions = find_all(content, search)
  if #positions > 1 and not opts.replace_all then
    return {
      error = fmt(
        "`old_string` matches %d places in the file. Include more surrounding lines to make it unique, or set `replace_all` to true to change every match",
        #positions
      ),
    }
  end

  local edited = splice(content, { search = search, replacement = new_string, positions = positions })
  if edited == content then
    return { error = "The edit made no changes to the file" }
  end

  return { content = edited }
end

return M
