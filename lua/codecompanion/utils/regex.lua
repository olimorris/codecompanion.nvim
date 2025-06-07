local M = {}

---Replace certain patterns in a string with a replacement
---@param str string The input string
---@param regex_pattern string The regex pattern to match
---@param replacement string The string to replace the matched pattern with (Don't include the regex pattern matching strings in the replacement)
---@return string The modified string with replacements
function M.replace(str, regex_pattern, replacement)
  local regex = vim.regex(regex_pattern)
  if not regex then
    return str
  end

  local lines = {}
  ---vim.regex doesn't consider \n as end of line, so we need to split the string into lines
  for _, line in ipairs(vim.split(str, "\n", { trimempty = true, plain = true })) do
    local start_pos, end_pos = regex:match_str(line)
    local iteration_count = 0
    local max_iterations = 1000 -- Arbitrary limit to prevent infinite loops
    while start_pos and end_pos do
      -- Break if the match is zero-width to prevent infinite loops
      if start_pos == end_pos then
        break
      end

      -- In order to preserve the whitespace after the found word
      local is_space = line:sub(end_pos, end_pos) == " "

      -- Make sure the replacement string doesn't include the given regex pattern matching strings, otherwise it will cause an infinite loop
      line = line:sub(1, start_pos) .. replacement .. line:sub((is_space and end_pos or end_pos + 1))

      -- Update start_pos and end_pos for the next match
      start_pos, end_pos = regex:match_str(line)

      -- Increment iteration count and break if it exceeds the limit
      iteration_count = iteration_count + 1
      if iteration_count > max_iterations then
        error("Infinite loop detected in regex_replace")
      end
    end
    table.insert(lines, line)
  end
  return table.concat(lines, "\n")
end

---Find the first occurrence of a pattern in a string handling multiline strings
---@param str string The input string
---@param regex_pattern string The regex pattern to search for
---@return number?,number? The start and end position of the match, or nil if not found
function M.find(str, regex_pattern)
  local regex = vim.regex(regex_pattern)
  if not regex then
    return nil, nil
  end
  ---vim.regex doesn't consider \n as end of line, so we need to split the string into lines
  for _, line in ipairs(vim.split(str, "\n", { trimempty = true, plain = true })) do
    local start_pos, end_pos = regex:match_str(line)
    if start_pos and end_pos then
      return start_pos, end_pos
    end
  end
  return nil, nil
end

return M
