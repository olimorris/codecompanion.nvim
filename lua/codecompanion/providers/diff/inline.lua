local diff_utils = require("codecompanion.providers.diff.utils")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local api = vim.api

---@class InlineDiffArgs
---@field bufnr integer Buffer number to apply diff to
---@field contents string[] Original content lines
---@field id string Unique identifier for this diff

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
  return diff_utils.calculate_hunks(old_lines, new_lines, context_lines)
end

---Apply visual highlights to hunks in a buffer with sign column indicators
---@param bufnr integer Buffer to apply highlights to
---@param hunks DiffHunk[] Hunks to highlight
---@param ns_id integer Namespace for extmarks
---@param line_offset? integer Line offset
---@param opts? table Options: {show_removed: boolean, full_width_removed: boolean, status?: string}
---@return integer[] extmark_ids
function InlineDiff.apply_hunk_highlights(bufnr, hunks, ns_id, line_offset, opts)
  opts = opts or { show_removed = true, full_width_removed = true, status = "pending" }
  return diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, line_offset, opts)
end

---Compares two content arrays for equality
---@param content1 string[] First content array
---@param content2 string[] Second content array
---@return boolean equal True if contents are identical
function InlineDiff:contents_equal(content1, content2)
  return diff_utils.contents_equal(content1, content2)
end

---Apply diff highlights to this instance
---@param old_lines string[]
---@param new_lines string[]
function InlineDiff:apply_diff_highlights(old_lines, new_lines)
  log:debug("[InlineDiff] Instance apply_diff_highlights called")
  local hunks = InlineDiff.calculate_hunks(old_lines, new_lines)
  local extmark_ids = InlineDiff.apply_hunk_highlights(self.bufnr, hunks, self.ns_id, 0, {
    show_removed = true,
    full_width_removed = true,
  })
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
