local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local api = vim.api
local diff_fn = vim.text.diff or vim.diff

---@class InlineDiffArgs
---@field bufnr integer Buffer number to apply diff to
---@field contents string[] Original content lines
---@field id string Unique identifier for this diff
---@class DiffHunk
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field old_lines string[]
---@field new_lines string[]
---@field context_before string[]
---@field context_after string[]

---@class InlineDiff
---@field bufnr integer
---@field contents string[]
---@field id string
---@field ns_id integer
---@field extmark_ids integer[]
---@field has_changes boolean
local InlineDiff = {}

---Creates a new InlineDiff instance and applies diff highlights
---@param args InlineDiffArgs
---@return InlineDiff
function InlineDiff.new(args)
  log:debug("[InlineDiff] Version 4 test - with virtual text")
  local self = setmetatable({
    bufnr = args.bufnr,
    contents = args.contents,
    id = args.id,
    ns_id = api.nvim_create_namespace(
      "codecompanion_inline_diff_" .. (args.id ~= nil and args.id or math.random(1, 100000))
    ),
    extmark_ids = {},
    has_changes = false,
  }, { __index = InlineDiff })
  ---@cast self InlineDiff

  local current_content = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  if self:contents_equal(self.contents, current_content) then
    log:debug("[InlineDiff] No changes detected")
    util.fire("DiffAttached", { diff = "inline", bufnr = self.bufnr, id = self.id })
    return self
  end
  log:debug("[InlineDiff] Changes detected - applying diff highlights")
  self.has_changes = true
  self:apply_diff_highlights(self.contents, current_content)
  util.fire("DiffAttached", { diff = "inline", bufnr = self.bufnr, id = self.id })
  return self
end

---Calculate diff hunks between two content arrays
---@param old_lines string[] Original content
---@param new_lines string[] New content
---@param context_lines? integer Number of context lines (default: 3)
---@return DiffHunk[] hunks
function InlineDiff.calculate_hunks(old_lines, new_lines, context_lines)
  context_lines = context_lines or 3
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
---@param hunks DiffHunk[] Hunks to highlight
---@param ns_id integer Namespace for extmarks
---@param line_offset? integer Line offset (currently unused, kept for compatibility)
---@param opts? table Options: {show_removed: boolean, full_width_removed: boolean}
---@return integer[] extmark_ids
function InlineDiff.apply_hunk_highlights(bufnr, hunks, ns_id, line_offset, opts)
  line_offset = line_offset or 0
  opts = opts or { show_removed = true, full_width_removed = true }
  local extmark_ids = {}

  log:debug("[InlineDiff] apply_hunk_highlights: %d hunks", #hunks)

  for hunk_idx, hunk in ipairs(hunks) do
    log:debug(
      "[InlineDiff] Processing hunk %d: old(%d,%d) new(%d,%d)",
      hunk_idx,
      hunk.old_start,
      hunk.old_count,
      hunk.new_start,
      hunk.new_count
    )
    -- Handle removed lines FIRST (virtual text above the change location)
    if opts.show_removed and #hunk.old_lines > 0 then
      local attach_line = math.max(0, hunk.new_start - 1)
      if attach_line >= api.nvim_buf_line_count(bufnr) then
        attach_line = api.nvim_buf_line_count(bufnr) - 1
      end
      local is_modification = #hunk.new_lines > 0
      local sign_hl = is_modification and "DiagnosticWarn" or "DiffDelete"
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
        priority = 100,
        sign_text = "▌",
        sign_hl_group = sign_hl,
      })
      table.insert(extmark_ids, extmark_id)
      log:debug(
        "[InlineDiff] Added %d removed lines as virtual text at line %d with %s sign",
        #hunk.old_lines,
        attach_line,
        sign_hl
      )
    end

    -- Handle added/modified lines (highlight in green)
    for i, new_line in ipairs(hunk.new_lines) do
      local line_idx = hunk.new_start + i - 2 -- Correct 0-based conversion
      if line_idx >= 0 and line_idx < api.nvim_buf_line_count(bufnr) then
        -- Determine change type
        local is_modification = #hunk.old_lines > 0
        local sign_hl = is_modification and "DiagnosticWarn" or "DiffAdd"

        local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
          line_hl_group = "DiffAdd",
          priority = 100,
          sign_text = "▌",
          sign_hl_group = sign_hl,
        })
        table.insert(extmark_ids, extmark_id)
        log:debug("[InlineDiff] Added green highlight at line %d with %s sign", line_idx, sign_hl)
      end
    end
  end

  log:debug("[InlineDiff] Applied %d total extmarks", #extmark_ids)
  return extmark_ids
end

---Compares two content arrays for equality
---@param content1 string[] First content array
---@param content2 string[] Second content array
---@return boolean equal True if contents are identical
function InlineDiff:contents_equal(content1, content2)
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

---Apply diff highlights to this instance (REFACTORED to use shared functions)
---@param old_lines string[]
---@param new_lines string[]
function InlineDiff:apply_diff_highlights(old_lines, new_lines)
  log:debug("[InlineDiff] Instance apply_diff_highlights called")
  local hunks = InlineDiff.calculate_hunks(old_lines, new_lines)
  log:debug("[InlineDiff] Calculated %d hunks", #hunks)
  local extmark_ids = InlineDiff.apply_hunk_highlights(self.bufnr, hunks, self.ns_id, 0, {
    show_removed = true,
    full_width_removed = true,
  })
  log:debug("[InlineDiff] Got %d extmark_ids from apply_hunk_highlights", #extmark_ids)
  vim.list_extend(self.extmark_ids, extmark_ids)
  log:debug("[InlineDiff] Applied %d extmarks for diff visualization", #self.extmark_ids)
end

---Clears all diff highlights and extmarks
function InlineDiff:clear_highlights()
  if api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_clear_namespace(self.bufnr, self.ns_id, 0, -1)
  end
  self.extmark_ids = {}
end

---Accepts the diff changes and clears highlights
function InlineDiff:accept()
  log:debug("[InlineDiff] Accept called")
  util.fire("DiffAccepted", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = true })
  self:clear_highlights()
end

---Rejects the diff changes, restores original content, and clears highlights
function InlineDiff:reject()
  util.fire("DiffRejected", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = false })
  log:debug("[InlineDiff] Reject called")
  if api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.contents)
  end
  self:clear_highlights()
end

---Cleans up the diff instance and fires detachment event
function InlineDiff:teardown()
  log:debug("[InlineDiff] Teardown called")
  self:clear_highlights()
  util.fire("DiffDetached", { diff = "inline", bufnr = self.bufnr, id = self.id })
end

return InlineDiff
