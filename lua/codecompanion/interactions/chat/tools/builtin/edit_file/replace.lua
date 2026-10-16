local fmt = string.format

local M = {}

local CURLY_QUOTES = { ["‘"] = "'", ["’"] = "'", ["“"] = '"', ["”"] = '"' }
local CURLY_QUOTE_PATTERN = "\226\128[\152\153\156\157]"
local EM_DASH = "\226\128\148"
local EN_DASH = "\226\128\147"
local LETTER = "[%a\128-\255]"

---@class CodeCompanion.Tool.EditFile.NormalizedText
---@field text string
---@field to_original fun(position: number): number

---Replace every match of the pattern, keeping a way to map positions back to the original text
---@param text string
---@param opts { pattern: string, replacements: table<string, string> }
---@return CodeCompanion.Tool.EditFile.NormalizedText
local function normalize(text, opts)
  local shifts = {}
  local removed = 0
  local normalized = text:gsub("()(" .. opts.pattern .. ")", function(position, match)
    local replacement = opts.replacements[match]
    removed = removed + #match - #replacement
    table.insert(shifts, { from = position + #match - removed, shift = removed })
    return replacement
  end)

  return {
    text = normalized,
    to_original = function(position)
      local low, high, shift = 1, #shifts, 0
      while low <= high do
        local middle = math.floor((low + high) / 2)
        if shifts[middle].from <= position then
          shift = shifts[middle].shift
          low = middle + 1
        else
          high = middle - 1
        end
      end
      return position + shift
    end,
  }
end

---Return the start and exclusive finish of every non-overlapping match
---@param content string
---@param opts { search: string }
---@return { start: number, finish: number }[]
local function find_all(content, opts)
  local spans = {}
  local from = 1
  while true do
    local start = content:find(opts.search, from, true)
    if not start then
      return spans
    end
    table.insert(spans, { start = start, finish = start + #opts.search })
    from = start + #opts.search
  end
end

---Find every match in the original content, ignoring line endings and, if nothing matches, curly quotes
---@param content string
---@param opts { search: string }
---@return { spans: { start: number, finish: number }[], restyle: boolean }
local function find_matches(content, opts)
  local lf = normalize(content, { pattern = "\r\n", replacements = { ["\r\n"] = "\n" } })
  local spans = find_all(lf.text, { search = opts.search })
  local to_original = lf.to_original
  local restyle = false

  if #spans == 0 then
    local quotes = { pattern = CURLY_QUOTE_PATTERN, replacements = CURLY_QUOTES }
    local straight = normalize(lf.text, quotes)
    spans = find_all(straight.text, { search = normalize(opts.search, quotes).text })
    to_original = function(position)
      return lf.to_original(straight.to_original(position))
    end
    restyle = true
  end

  for _, span in ipairs(spans) do
    span.start = to_original(span.start)
    span.finish = to_original(span.finish)
  end
  return { spans = spans, restyle = restyle }
end

---@param text string
---@param opts { position: number }
---@return boolean
local function is_opening_quote(text, opts)
  local position = opts.position
  if position == 1 then
    return true
  end
  local preceding = text:sub(position - 3, position - 1)
  return text:sub(position - 1, position - 1):match("[%s%(%[{]") ~= nil or preceding == EM_DASH or preceding == EN_DASH
end

---Curl the straight quotes in the text to match the curly quotes in the file
---@param text string
---@param opts { matched: string }
---@return string
local function apply_quote_style(text, opts)
  local has_curly_double = opts.matched:find("“", 1, true) or opts.matched:find("”", 1, true)
  local has_curly_single = opts.matched:find("‘", 1, true) or opts.matched:find("’", 1, true)

  return (
    text:gsub("()(['\"])", function(position, quote)
      if quote == '"' and has_curly_double then
        return is_opening_quote(text, { position = position }) and "“" or "”"
      end
      if quote == "'" and has_curly_single then
        local is_apostrophe = text:sub(position - 1, position - 1):match(LETTER)
          and text:sub(position + 1, position + 1):match(LETTER)
        return (not is_apostrophe and is_opening_quote(text, { position = position })) and "‘" or "’"
      end
    end)
  )
end

---@param content string
---@param opts { position: number }
---@return boolean
local function is_line_start(content, opts)
  return opts.position == 1 or content:sub(opts.position - 1, opts.position - 1) == "\n"
end

---Use the line ending inside the match, or else the one on the line the match sits on
---@param content string
---@param opts { span: { start: number, finish: number } }
---@return string
local function get_line_ending(content, opts)
  local span = opts.span
  return content:sub(span.start, span.finish - 1):match("\r?\n") or content:match("\r?\n", span.finish) or "\n"
end

---Replace each match, consuming the trailing newline when whole lines are deleted
---@param content string
---@param opts { spans: { start: number, finish: number }[], replace: fun(match: { text: string, line_ending: string }): string }
---@return string
local function splice(content, opts)
  local parts = {}
  local cursor = 1

  for _, span in ipairs(opts.spans) do
    local matched = content:sub(span.start, span.finish - 1)
    local replacement = opts.replace({ text = matched, line_ending = get_line_ending(content, { span = span }) })
    local finish = span.finish
    if replacement == "" and matched:sub(-1) ~= "\n" and is_line_start(content, { position = span.start }) then
      finish = finish + #(content:match("^\r?\n", finish) or "")
    end
    table.insert(parts, content:sub(cursor, span.start - 1))
    table.insert(parts, replacement)
    cursor = finish
  end
  table.insert(parts, content:sub(cursor))

  return table.concat(parts)
end

---Replace `old_string` with `new_string`, keeping the file's line endings and curly quotes
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

  local matches = find_matches(content, { search = old_string })
  if #matches.spans == 0 then
    return {
      error = "`old_string` was not found in the file. It must match the file exactly, including whitespace and indentation",
    }
  end

  if #matches.spans > 1 and not opts.replace_all then
    return {
      error = fmt(
        "`old_string` matches %d places in the file. Include more surrounding lines to make it unique, or set `replace_all` to true to change every match",
        #matches.spans
      ),
    }
  end

  local edited = splice(content, {
    spans = matches.spans,
    replace = function(match)
      local replacement = matches.restyle and apply_quote_style(new_string, { matched = match.text }) or new_string
      return (replacement:gsub("\n", match.line_ending))
    end,
  })
  if edited == content then
    return { error = "The edit made no changes to the file" }
  end

  return { content = edited }
end

return M
