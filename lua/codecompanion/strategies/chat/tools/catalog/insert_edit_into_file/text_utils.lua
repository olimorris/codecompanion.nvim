--[[Text normalization and similarity utilities for insert_edit_into_file]]

local M = {}

---Normalize whitespace for better matching
---@param text string The text to normalize
---@param mode? "aggressive"|"standard"|"simple" Normalization mode (default: "standard")
---@return string The normalized text
function M.normalize_whitespace(text, mode)
  mode = mode or "standard"
  local result

  if mode == "aggressive" then
    -- Remove all extra whitespace, normalize indentation
    result = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return result
  elseif mode == "simple" then
    -- Collapse multiple spaces to single space and trim
    result = vim.trim(text):gsub("%s+", " ")
    return result
  else -- standard
    -- Just trim and normalize line endings
    result = vim.trim(text):gsub("\r\n", "\n")
    return result
  end
end

---Remove empty trailing line if present (handles "text\n" patterns)
---This normalizes LLM-generated text that often includes trailing newlines
---@param lines string[] Array of lines to normalize
---@return string[] Normalized lines without empty trailing line
function M.normalize_trailing_newline(lines)
  if #lines >= 2 and lines[#lines] == "" then
    return vim.list_slice(lines, 1, #lines - 1)
  end
  return lines
end

---Normalize empty lines for better LLM code block matching (conservative approach)
---@param text string Text to normalize empty lines in
---@return string Text with normalized empty lines
function M.normalize_empty_lines(text)
  -- Be more conservative - only normalize multiple consecutive empty lines to single
  -- and trim leading/trailing empty lines to preserve line positions
  local normalized = text
  -- Normalize multiple consecutive empty lines to at most 1
  normalized = normalized:gsub("\n\n\n+", "\n\n")
  -- Trim leading empty lines
  normalized = normalized:gsub("^%s*\n", "")
  -- Trim trailing empty lines
  normalized = normalized:gsub("\n%s*$", "")

  return normalized
end

---Normalize punctuation: remove trailing punctuation, normalize spacing
---@param text string The text to normalize
---@return string The text with normalized punctuation
function M.normalize_punctuation(text)
  local result = vim
    .trim(text)
    -- Remove trailing commas and semicolons
    :gsub(",%s*$", "")
    :gsub(";%s*$", "")
    -- Normalize comma and semicolon spacing
    :gsub("%s*,%s*", ",")
    :gsub("%s*;%s*", ";")
    -- Normalize parentheses spacing
    :gsub("%s*%(%s*", "(")
    :gsub("%s*%)%s*", ")")
    -- Normalize bracket spacing
    :gsub("%s*%[%s*", "[")
    :gsub("%s*%]%s*", "]")
    -- Normalize brace spacing
    :gsub("%s*{%s*", "{")
    :gsub("%s*}%s*", "}")
  return result
end

---Remove common indentation from lines
---Useful for indentation-flexible matching
---@param lines string[] Array of lines to process
---@return string[] Array of lines with common indentation removed
function M.remove_common_indentation(lines)
  local non_empty_lines = vim.tbl_filter(function(line)
    return vim.trim(line) ~= ""
  end, lines)

  if #non_empty_lines == 0 then
    return lines
  end

  -- Find minimum indentation
  local min_indent = math.huge
  for _, line in ipairs(non_empty_lines) do
    local indent = line:match("^(%s*)")
    min_indent = math.min(min_indent, #indent)
  end

  if min_indent == 0 or min_indent == math.huge then
    return lines
  end

  -- Remove common indentation
  local result = {}
  for _, line in ipairs(lines) do
    if vim.trim(line) == "" then
      table.insert(result, line)
    else
      table.insert(result, line:sub(min_indent + 1))
    end
  end
  return result
end

-- =============================
-- String Similarity Utilities
-- =============================

---Levenshtein distance for similarity scoring
---Uses dynamic programming to compute edit distance between two strings
---@param a string
---@param b string
---@return number The edit distance between the two strings
local function levenshtein_distance(a, b)
  if a == "" then
    return #b
  end
  if b == "" then
    return #a
  end

  local matrix = {}
  for i = 0, #a do
    matrix[i] = { [0] = i }
  end
  for j = 0, #b do
    matrix[0][j] = j
  end

  for i = 1, #a do
    for j = 1, #b do
      local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
      matrix[i][j] = math.min(
        matrix[i - 1][j] + 1, -- deletion
        matrix[i][j - 1] + 1, -- insertion
        matrix[i - 1][j - 1] + cost -- substitution
      )
    end
  end

  return matrix[#a][#b]
end

---Calculate similarity score between two strings (0.0 to 1.0)
---Returns 1.0 for identical strings, 0.0 for completely different strings
---@param a string
---@param b string
---@return number Similarity score from 0.0 (no similarity) to 1.0 (identical)
function M.similarity_score(a, b)
  if a == b then
    return 1.0
  end
  local max_len = math.max(#a, #b)
  if max_len == 0 then
    return 1.0
  end
  return 1.0 - (levenshtein_distance(a, b) / max_len)
end

---Calculate line similarity with better fuzzy matching
---Tries exact match first, then trimmed match, then edit distance
---@param line1 string
---@param line2 string
---@return number Similarity score between 0 and 1
function M.calculate_line_similarity(line1, line2)
  if line1 == line2 then
    return 1.0
  end

  local trimmed1 = vim.trim(line1)
  local trimmed2 = vim.trim(line2)

  if trimmed1 == trimmed2 then
    return 0.95 -- High similarity for whitespace-only differences
  end

  -- Use edit distance for fuzzy comparison
  return M.similarity_score(trimmed1, trimmed2)
end

return M
