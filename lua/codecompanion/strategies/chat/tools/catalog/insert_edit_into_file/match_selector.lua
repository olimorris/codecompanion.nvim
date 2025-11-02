--[[
Error handling and diagnostics for edit operations

This module provides helpful error messages and conflict detection when edits fail.
It helps LLMs understand what went wrong and how to fix it.

## Key Functions:

1. **format_helpful_error**:
   - Generates context-aware error messages with actionable suggestions
   - Handles missing fields (oldText, newText)
   - Provides examples of correct usage
   - Points to specific line/edit that failed

2. **detect_edit_conflicts**:
   - Finds overlapping edits (same region modified by multiple edits)
   - Prevents conflicting changes that would corrupt the file
   - Reports which edits conflict with each other
--]]

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

  -- Handle missing required fields
  if failed_result.error == "missing_oldText" then
    append(fmt("Edit #%d failed: Missing required field 'oldText'", failed_edit_index))
    append(
      "",
      "CRITICAL ERROR: Every edit MUST have both 'oldText' and 'newText' fields.",
      "",
      "Check your JSON structure:",
      '✓ Correct: {"oldText": "text to find", "newText": "replacement text"}',
      '✗ Wrong: {"newText": "replacement text"}  ← Missing oldText!',
      "",
      "Common causes:",
      "- Putting 'filepath' or 'explanation' inside the edits array (should be at top level)",
      "- Forgetting to include the text you want to find/replace",
      "- Malformed JSON structure"
    )
    return table.concat(error_parts, "\n")
  end

  if failed_result.error == "missing_newText" then
    append(fmt("Edit #%d failed: Missing required field 'newText'", failed_edit_index))
    append(
      "",
      "CRITICAL ERROR: Every edit MUST have both 'oldText' and 'newText' fields.",
      "",
      "Check your JSON structure:",
      '✓ Correct: {"oldText": "text to find", "newText": "replacement text"}',
      '✗ Wrong: {"oldText": "text to find"}  ← Missing newText!',
      "",
      'Note: newText can be an empty string "" for deletions, but the field must exist.'
    )
    return table.concat(error_parts, "\n")
  end

  -- Dynamic parts
  append(fmt("Edit #%d failed: %s", failed_edit_index, failed_result.error))

  -- Add context about the failed edit
  local old_text_preview = failed_edit.oldText
  if old_text_preview and #old_text_preview > 100 then
    old_text_preview = old_text_preview:sub(1, 100) .. "..."
  end
  if old_text_preview then
    -- Use %s with manual escaping instead of %q to avoid misleading display of tabs as \9
    local escaped_preview = old_text_preview:gsub("\t", "\\t"):gsub("\n", "\\n"):gsub("\r", "\\r")
    append(fmt("Failed edit was looking for: %s", escaped_preview))
  end

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
    append(
      "",
      fmt(
        "Note: %d edit(s) before this one were processed successfully, but NO changes were written to the file because this edit failed.",
        #failed_result.partial_results
      ),
      "The file remains unchanged. All edits must succeed for any changes to be applied."
    )
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

return M
