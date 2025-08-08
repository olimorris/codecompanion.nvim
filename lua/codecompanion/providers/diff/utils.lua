local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion.Diff.Utils
local M = {}

---@class CodeCompanion.Diff.Utils.DiffHunk
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field old_lines string[]
---@field new_lines string[]
---@field context_before string[]
---@field context_after string[]

---Calculate diff hunks between two content arrays
---@param old_lines string[] Original content
---@param new_lines string[] New content
---@param context_lines? integer Number of context lines (default: 3)
---@return CodeCompanion.Diff.Utils.DiffHunk[] hunks
function M.calculate_hunks(old_lines, new_lines, context_lines)
  context_lines = context_lines or 3
  local diff_fn = vim.text.diff or vim.diff
  local old_text = table.concat(old_lines, "\n")
  local new_text = table.concat(new_lines, "\n")
  local ok, diff_result = pcall(diff_fn, old_text, new_text, {
    result_type = "indices",
    algorithm = "histogram",
  })
  if not ok or not diff_result or #diff_result == 0 then
    return {}
  end
  local hunks = {}
  for _, hunk in ipairs(diff_result) do
    local old_start, old_count, new_start, new_count = unpack(hunk)
    -- Extract changed lines
    local hunk_old_lines = {}
    for i = 0, old_count - 1 do
      local line_idx = old_start + i
      if old_lines[line_idx] then
        table.insert(hunk_old_lines, old_lines[line_idx])
      end
    end
    local hunk_new_lines = {}
    for i = 0, new_count - 1 do
      local line_idx = new_start + i
      if new_lines[line_idx] then
        table.insert(hunk_new_lines, new_lines[line_idx])
      end
    end
    -- Extract context
    local context_before = {}
    local context_start = math.max(1, old_start - context_lines)
    for i = context_start, old_start - 1 do
      if old_lines[i] then
        table.insert(context_before, old_lines[i])
      end
    end
    local context_after = {}
    local context_end = math.min(#old_lines, old_start + old_count + context_lines - 1)
    for i = old_start + old_count, context_end do
      if old_lines[i] then
        table.insert(context_after, old_lines[i])
      end
    end
    table.insert(hunks, {
      old_start = old_start,
      old_count = old_count,
      new_start = new_start,
      new_count = new_count,
      old_lines = hunk_old_lines,
      new_lines = hunk_new_lines,
      context_before = context_before,
      context_after = context_after,
    })
  end

  return hunks
end

---Apply visual highlights to hunks in a buffer with sign column indicators
---@param bufnr integer Buffer to apply highlights to
---@param hunks CodeCompanion.Diff.Utils.DiffHunk[] Hunks to highlight
---@param ns_id integer Namespace for extmarks
---@param line_offset? integer Line offset (default: 0)
---@param opts? table Options: {show_removed: boolean, full_width_removed: boolean, status: string}
---@return integer[] extmark_ids
function M.apply_hunk_highlights(bufnr, hunks, ns_id, line_offset, opts)
  line_offset = line_offset or 0
  opts = opts or { show_removed = true, full_width_removed = true, status = "pending" }
  local extmark_ids = {}
  for _, hunk in ipairs(hunks) do
    -- Handle removed lines FIRST (virtual text above the change location)
    if opts.show_removed and #hunk.old_lines > 0 then
      local attach_line = math.max(0, hunk.new_start - 1 + line_offset)
      if attach_line >= api.nvim_buf_line_count(bufnr) then
        attach_line = api.nvim_buf_line_count(bufnr) - 1
      end
      local is_modification = #hunk.new_lines > 0
      local sign_hl = M.get_sign_highlight_for_change("removed", is_modification, opts.status)
      -- Create virtual text for ALL removed lines in this hunk
      local virt_lines = {}
      for _, old_line in ipairs(hunk.old_lines) do
        local display_line = old_line
        local padding = opts.full_width_removed and math.max(0, vim.o.columns - #display_line - 2) or 0
        table.insert(virt_lines, { { display_line .. string.rep(" ", padding), "DiffDelete" } })
      end
      -- Single extmark for all removed lines in this hunk
      local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, attach_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        virt_lines_overflow = "scroll",
        priority = 100,
        sign_text = "▌",
        sign_hl_group = sign_hl,
      })
      table.insert(extmark_ids, extmark_id)
      log:debug(
        "[providers::diff::utils::apply_hunk_highlights] Added %d removed lines as virtual text at line %d with %s sign",
        #hunk.old_lines,
        attach_line,
        sign_hl
      )
    end

    -- Handle added/modified lines (highlight in green/red based on status)
    for i, _ in ipairs(hunk.new_lines) do
      local line_idx = hunk.new_start + i - 2 + line_offset -- Correct 0-based conversion
      if line_idx >= 0 and line_idx < api.nvim_buf_line_count(bufnr) then
        -- Determine change type and status
        local is_modification = #hunk.old_lines > 0
        local sign_hl = M.get_sign_highlight_for_change("added", is_modification, opts.status)
        local line_hl = opts.status == "rejected" and "DiffDelete" or "DiffAdd"
        local sign_text = opts.status == "rejected" and "✗" or "▌"
        local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
          line_hl_group = line_hl,
          priority = 100,
          sign_text = sign_text,
          sign_hl_group = sign_hl,
        })
        table.insert(extmark_ids, extmark_id)
        log:debug(
          "[providers::diff::utils::apply_hunk_highlights] Added %s highlight at line %d with %s sign",
          line_hl,
          line_idx,
          sign_hl
        )
      end
    end
  end

  log:debug("[providers::diff::utils::apply_hunk_highlights] Applied %d total extmarks", #extmark_ids)
  return extmark_ids
end

---Get appropriate sign highlight color for a change type
---@param change_type "added"|"removed" Type of change
---@param is_modification boolean Whether this is a modification or pure add/delete
---@param status? string Status of the edit operation ("pending"|"accepted"|"rejected")
---@return string highlight_group
function M.get_sign_highlight_for_change(change_type, is_modification, status)
  status = status or "pending"
  if status == "rejected" then
    return "DiagnosticError" -- Red for rejected changes
  end
  if change_type == "removed" then
    return is_modification and "DiagnosticWarn" or "DiagnosticError" -- Orange for modifications, red for deletions
  elseif change_type == "added" then
    return is_modification and "DiagnosticWarn" or "DiagnosticOk" -- Orange for modifications, green for pure additions
  end

  return "DiagnosticWarn"
end

---Compare two content arrays for equality
---@param content1 string[] First content array
---@param content2 string[] Second content array
---@return boolean equal True if contents are identical
function M.contents_equal(content1, content2)
  if #content1 ~= #content2 then
    return false
  end
  for i = 1, #content1 do
    if content1[i] ~= content2[i] then
      return false
    end
  end
  return true
end

---Create a unified diff display combining multiple hunks
---@param hunks CodeCompanion.Diff.Utils.DiffHunk[] Hunks to display
---@param opts? table Options for diff display
---@return string[] lines, table ranges Line content and highlighting ranges
function M.create_unified_diff_display(hunks, opts)
  opts = opts or {}
  local combined_lines = {}
  local line_types = {} -- track if line is context, removed, or added
  local hunk_types = {} -- track modification type per line
  -- Build the diff using unified diff logic
  for hunk_idx, hunk in ipairs(hunks) do
    local hunk_is_modification = #hunk.old_lines > 0 and #hunk.new_lines > 0
    -- Add context before (only for first hunk)
    if hunk_idx == 1 then
      for _, line in ipairs(hunk.context_before) do
        table.insert(combined_lines, line)
        table.insert(line_types, "context")
        table.insert(hunk_types, "context")
      end
    end
    -- Add removed lines first
    for _, line in ipairs(hunk.old_lines) do
      table.insert(combined_lines, line)
      table.insert(line_types, "removed")
      table.insert(hunk_types, hunk_is_modification and "modification" or "deletion")
    end
    -- Add new lines
    for _, line in ipairs(hunk.new_lines) do
      table.insert(combined_lines, line)
      table.insert(line_types, "added")
      table.insert(hunk_types, hunk_is_modification and "modification" or "addition")
    end
    -- Add context after (only for last hunk)
    if hunk_idx == #hunks then
      for _, line in ipairs(hunk.context_after) do
        table.insert(combined_lines, line)
        table.insert(line_types, "context")
        table.insert(hunk_types, "context")
      end
    end
  end
  -- Calculate ranges for highlighting
  local removed_ranges = {}
  local added_ranges = {}
  local current_removed_start = nil
  local current_added_start = nil
  for i, line_type in ipairs(line_types) do
    local line_idx = i - 1 -- 0-based for extmarks
    if line_type == "removed" then
      if not current_removed_start then
        current_removed_start = line_idx
      end
      -- If next line is not removed, close this range
      if i == #combined_lines or line_types[i + 1] ~= "removed" then
        table.insert(removed_ranges, {
          current_removed_start,
          line_idx,
          is_modification = hunk_types[i] == "modification",
        })
        current_removed_start = nil
      end
    elseif line_type == "added" then
      if not current_added_start then
        current_added_start = line_idx
      end
      -- If next line is not added, close this range
      if i == #combined_lines or line_types[i + 1] ~= "added" then
        table.insert(added_ranges, {
          current_added_start,
          line_idx,
          is_modification = hunk_types[i] == "modification",
        })
        current_added_start = nil
      end
    end
  end
  return combined_lines,
    {
      removed_ranges = removed_ranges,
      added_ranges = added_ranges,
      line_types = line_types,
      hunk_types = hunk_types,
    }
end

return M
