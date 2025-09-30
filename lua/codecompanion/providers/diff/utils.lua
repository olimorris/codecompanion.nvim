local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion.Diff.Utils
local M = {}

---@class CodeCompanion.Diff.Utils.DiffHunk
---@field original_start number
---@field original_count number
---@field updated_start number
---@field updated_count number
---@field removed_lines string[]
---@field added_lines string[]
---@field context_before string[]
---@field context_after string[]

---Calculate diff hunks between two content arrays
---@param removed_lines string[]
---@param added_lines string[]
---@param context_lines? number Number of context lines (default: 3)
---@return CodeCompanion.Diff.Utils.DiffHunk[] hunks
function M.calculate_hunks(removed_lines, added_lines, context_lines)
  context_lines = context_lines or 3

  local diff_engine = vim.text.diff or vim.diff
  local original_text = table.concat(removed_lines, "\n")
  local updated_text = table.concat(added_lines, "\n")
  local ok, diff_result = pcall(diff_engine, original_text, updated_text, {
    result_type = "indices",
    algorithm = "histogram",
  })

  if not ok or not diff_result or #diff_result == 0 then
    return {}
  end

  local hunks = {}
  for _, hunk in ipairs(diff_result) do
    local original_start, original_count, updated_start, updated_count = unpack(hunk)

    -- Extract changed lines
    local original_hunk_lines = {}
    for i = 0, original_count - 1 do
      local original_line_index = original_start + i
      if removed_lines[original_line_index] then
        table.insert(original_hunk_lines, removed_lines[original_line_index])
      end
    end

    local updated_hunk_lines = {}
    for i = 0, updated_count - 1 do
      local original_line_index = updated_start + i
      if added_lines[original_line_index] then
        table.insert(updated_hunk_lines, added_lines[original_line_index])
      end
    end

    -- Extract context
    local context_before = {}
    local context_start = math.max(1, original_start - context_lines)
    for i = context_start, original_start - 1 do
      if removed_lines[i] then
        table.insert(context_before, removed_lines[i])
      end
    end

    local context_after = {}
    local context_end = math.min(#removed_lines, original_start + original_count + context_lines - 1)
    for i = original_start + original_count, context_end do
      if removed_lines[i] then
        table.insert(context_after, removed_lines[i])
      end
    end
    table.insert(hunks, {
      original_start = original_start,
      original_count = original_count,
      updated_start = updated_start,
      updated_count = updated_count,
      removed_lines = original_hunk_lines,
      added_lines = updated_hunk_lines,
      context_before = context_before,
      context_after = context_after,
    })
  end

  return hunks
end

---Apply visual highlights to hunks in a buffer with sign column indicators
---@param bufnr number
---@param hunks CodeCompanion.Diff.Utils.DiffHunk
---@param ns_id number
---@param line_offset? number
---@param opts? {show_removed: boolean, full_width_removed: boolean, status: string}
---@return number[] extmark_ids
function M.apply_hunk_highlights(bufnr, hunks, ns_id, line_offset, opts)
  line_offset = line_offset or 0
  opts = opts or { show_removed = true, full_width_removed = true, status = "pending" }
  local extmark_ids = {}

  -- Get sign configuration from config (lazy load to avoid circular dependency)
  local config = require("codecompanion.config")
  local diff_signs_config = config.display.diff.provider_opts.inline.diff_signs or {}
  local signs = diff_signs_config.signs or {}
  local sign_text = signs.text or "▌"
  local highlight_groups = signs.highlight_groups
    or {
      addition = "DiagnosticOk",
      deletion = "DiagnosticError",
      modification = "DiagnosticWarn",
    }

  for _, hunk in ipairs(hunks) do
    -- Handle removed lines FIRST (virtual text above the change location)
    if opts.show_removed and #hunk.removed_lines > 0 then
      local attach_line = math.max(0, hunk.updated_start - 1 + line_offset)
      if attach_line >= api.nvim_buf_line_count(bufnr) then
        attach_line = api.nvim_buf_line_count(bufnr) - 1
      end

      local is_modified_hunk = #hunk.added_lines > 0
      local sign_hl = M.get_sign_highlight_for_change("removed", is_modified_hunk, highlight_groups)

      -- Create virtual text for ALL removed lines in this hunk
      local virt_lines = {}
      for _, old_line in ipairs(hunk.removed_lines) do
        local display_line = old_line
        local padding = opts.full_width_removed and math.max(0, vim.o.columns - #display_line - 2) or 0
        table.insert(virt_lines, { { display_line .. string.rep(" ", padding), "DiffDelete" } })
      end

      -- Single extmark for all removed lines in this hunk
      local _, extmark_id = pcall(api.nvim_buf_set_extmark, bufnr, ns_id, attach_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        virt_lines_overflow = "scroll",
        priority = 100,
        sign_text = sign_text,
        sign_hl_group = sign_hl,
      })
      table.insert(extmark_ids, extmark_id)
      log:trace(
        "[providers::diff::utils::apply_hunk_highlights] Added %d removed lines as virtual text at line %d with %s sign",
        #hunk.removed_lines,
        attach_line,
        sign_hl
      )
    end

    -- Handle added/modified lines (highlight in green/red based on status)
    for i, _ in ipairs(hunk.added_lines) do
      local target_row = hunk.updated_start + i - 2 + line_offset -- Correct 0-based conversion
      if target_row >= 0 and target_row < api.nvim_buf_line_count(bufnr) then
        -- Determine change type and status
        local is_modified_hunk = #hunk.removed_lines > 0
        local sign_hl = M.get_sign_highlight_for_change("added", is_modified_hunk, highlight_groups)
        local line_hl = "DiffAdd"
        local _, extmark_id = pcall(api.nvim_buf_set_extmark, bufnr, ns_id, target_row, 0, {
          line_hl_group = line_hl,
          priority = 100,
          sign_text = sign_text,
          sign_hl_group = sign_hl,
        })
        table.insert(extmark_ids, extmark_id)
        log:trace(
          "[providers::diff::utils::apply_hunk_highlights] Added %s highlight at line %d with %s sign",
          line_hl,
          target_row,
          sign_hl
        )
      end
    end
  end

  log:trace("[providers::diff::utils::apply_hunk_highlights] Applied %d total extmarks", #extmark_ids)
  return extmark_ids
end

---Get appropriate sign highlight color for a change type
---@param change_kind "added"|"removed"
---@param is_modified boolean
---@param hl_groups table
---@return string
function M.get_sign_highlight_for_change(change_kind, is_modified, hl_groups)
  hl_groups = hl_groups
    or {
      addition = "DiagnosticOk",
      deletion = "DiagnosticError",
      modification = "DiagnosticWarn",
    }

  if change_kind == "removed" then
    return is_modified and hl_groups.modification or hl_groups.deletion
  elseif change_kind == "added" then
    return is_modified and hl_groups.modification or hl_groups.addition
  end

  return hl_groups.modification
end

---Determine if two content arrays are equal
---@param content1 string[]
---@param content2 string[]
---@return boolean
function M.are_contents_equal(content1, content2)
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

return M
