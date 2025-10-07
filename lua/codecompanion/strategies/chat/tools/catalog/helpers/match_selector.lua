local log = require("codecompanion.utils.log")

local M = {}
local fmt = string.format

---Generate helpful error messages for failed matches
---@param failed_result table The failed result containing error information
---@param original_edits table[] Array of original edit operations
---@return string The formatted error message
function M.format_helpful_error(failed_result, original_edits)
  local error_parts = {}
  local function append(...)
    for i = 1, select("#", ...) do
      error_parts[#error_parts + 1] = select(i, ...)
    end
  end

  local failed_edit_index = failed_result.failed_at_edit or 1
  local failed_edit = original_edits[failed_edit_index]

  if not failed_edit then
    return "Unknown error occurred during edit processing"
  end

  -- Dynamic parts
  append(fmt("Edit #%d failed: %s", failed_edit_index, failed_result.error))

  -- Add context about the failed edit
  local old_text_preview = failed_edit.oldText
  if #old_text_preview > 100 then
    old_text_preview = old_text_preview:sub(1, 100) .. "..."
  end
  append(fmt("Failed edit was looking for: %q", old_text_preview))

  -- Handle specific error types
  if failed_result.error == "ambiguous_matches" and failed_result.matches then
    append("", fmt("Found %d similar matches:", #failed_result.matches))

    for i, match in ipairs(failed_result.matches) do
      if i > 5 then -- Limit to first 5 matches
        append(fmt("... and %d more matches", #failed_result.matches - 5))
        break
      end

      local line_info = ""
      if match.start_line then
        line_info = fmt(" (line %d)", match.start_line)
      end

      local preview = match.matched_text:sub(1, 60)
      if #match.matched_text > 60 then
        preview = preview .. "..."
      end

      append(fmt("  %d. Confidence %.0f%%%s: %q", i, match.confidence * 100, line_info, preview))
    end

    append(
      "",
      "To fix this:",
      "- Add more surrounding context to make oldText unique",
      "- Include function names, comments, or unique variable names",
      "- Or set 'replaceAll: true' to change all occurrences"
    )
  elseif failed_result.error:find("No confident matches found") then
    append(
      "",
      "The text could not be found in the file. This might be because:",
      "- The text has different formatting (spaces, tabs, line breaks)",
      "- The file content has changed since you last read it",
      "- There are typos in the text to find",
      "",
      "Try:",
      "- Use the read_file tool to see the current file content",
      "- Copy the exact text from the file, including formatting",
      "- Include more surrounding context to help locate the text"
    )
  elseif failed_result.error == "conflicting_edits" then
    append(
      "",
      "Multiple edits are trying to modify overlapping text.",
      "Please combine conflicting edits into a single edit operation."
    )
  end

  -- Add information about successful edits if any
  if failed_result.partial_results and #failed_result.partial_results > 0 then
    append("", fmt("Note: %d edit(s) before this one completed successfully.", #failed_result.partial_results))
  end

  return table.concat(error_parts, "\n")
end

---Detect if multiple edits conflict with each other
---@param content string The file content to check for conflicts
---@param edits table[] Array of edit operations
---@return table[] Array of detected conflicts
function M.detect_edit_conflicts(content, edits)
  local edit_positions = {}
  local conflicts = {}

  -- First, find positions of all edits
  for i, edit in ipairs(edits) do
    -- For conflict detection, we just need approximate positions
    local start_pos = content:find(edit.oldText, 1, true)
    if start_pos then
      local end_pos = start_pos + #edit.oldText - 1
      table.insert(edit_positions, {
        index = i,
        start_pos = start_pos,
        end_pos = end_pos,
        edit = edit,
      })
    end
  end

  -- Check for overlaps
  for i = 1, #edit_positions do
    for j = i + 1, #edit_positions do
      local edit1 = edit_positions[i]
      local edit2 = edit_positions[j]

      -- Check if ranges overlap
      if not (edit1.end_pos < edit2.start_pos or edit2.end_pos < edit1.start_pos) then
        table.insert(conflicts, {
          edit1_index = edit1.index,
          edit2_index = edit2.index,
          description = fmt(
            "Edit #%d and Edit #%d try to modify overlapping text at position %d-%d",
            edit1.index,
            edit2.index,
            math.max(edit1.start_pos, edit2.start_pos),
            math.min(edit1.end_pos, edit2.end_pos)
          ),
        })
      end
    end
  end

  return conflicts
end

---Find similar text in content that might be what the user meant
---@param content string The file content to search in
---@param target_text string The text to find similar matches for
---@param min_similarity? number Minimum similarity threshold (default: 0.7)
---@return table[] Array of similar matches with line, text, and similarity fields
function M.find_similar_text(content, target_text, min_similarity)
  min_similarity = min_similarity or 0.7
  local similar_matches = {}
  local content_lines = vim.split(content, "\n", { plain = true })
  local target_lines = vim.split(target_text, "\n", { plain = true })

  -- Simple similarity search - look for lines that are similar to target
  if #target_lines == 1 then
    -- Single line target - check each line
    local target_line = vim.trim(target_lines[1])

    for i, content_line in ipairs(content_lines) do
      local trimmed_content = vim.trim(content_line)
      local similarity = M.calculate_similarity(target_line, trimmed_content)

      if similarity >= min_similarity then
        table.insert(similar_matches, {
          line = i,
          text = content_line,
          similarity = similarity,
        })
      end
    end
  else
    -- Multi-line target - look for similar blocks
    for i = 1, #content_lines - #target_lines + 1 do
      local block_similarity = 0

      for j = 1, #target_lines do
        local content_line = vim.trim(content_lines[i + j - 1] or "")
        local target_line = vim.trim(target_lines[j])
        block_similarity = block_similarity + M.calculate_similarity(content_line, target_line)
      end

      local avg_similarity = block_similarity / #target_lines
      if avg_similarity >= min_similarity then
        local block_lines = {}
        for k = i, i + #target_lines - 1 do
          table.insert(block_lines, content_lines[k] or "")
        end

        table.insert(similar_matches, {
          line = i,
          text = table.concat(block_lines, "\n"),
          similarity = avg_similarity,
        })
      end
    end
  end

  -- Sort by similarity (best first)
  table.sort(similar_matches, function(a, b)
    return a.similarity > b.similarity
  end)

  return similar_matches
end

---Calculate simple similarity score between two strings
---@param str1 string First string to compare
---@param str2 string Second string to compare
---@return number Similarity score between 0.0 and 1.0
function M.calculate_similarity(str1, str2)
  if str1 == str2 then
    return 1.0
  end

  -- Simple character-based similarity
  local max_len = math.max(#str1, #str2)
  if max_len == 0 then
    return 1.0
  end

  local common_chars = 0
  local min_len = math.min(#str1, #str2)

  for i = 1, min_len do
    if str1:sub(i, i) == str2:sub(i, i) then
      common_chars = common_chars + 1
    end
  end

  return common_chars / max_len
end

return M
