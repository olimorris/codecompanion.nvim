local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local api = vim.api
local diff_fn = vim.text.diff or vim.diff

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

---Applies visual diff highlights using extmarks and virtual text
---@param old_lines string[] Original content lines
---@param new_lines string[] New content lines
function InlineDiff:apply_diff_highlights(old_lines, new_lines)
  local old_text = table.concat(old_lines, "\n")
  local new_text = table.concat(new_lines, "\n")
  log:debug("[InlineDiff] Generating diff between %d and %d chars", #old_text, #new_text)
  local ok, diff_result = pcall(diff_fn, old_text, new_text, {
    result_type = "indices",
    algorithm = "histogram",
  })
  ---@cast diff_result integer[][]?
  if not ok or not diff_result or #diff_result == 0 then
    log:debug("[InlineDiff] No diff result generated")
    return
  end
  log:debug("[InlineDiff] Processing %d diff hunks", #diff_result)
  -- Process each hunk
  for hunk_idx, hunk in ipairs(diff_result) do
    local old_start, old_count, new_start, new_count = unpack(hunk)
    log:debug("[InlineDiff] Hunk %d: old(%d,%d) new(%d,%d)", hunk_idx, old_start, old_count, new_start, new_count)
    -- Handle removed lines (show as virtual text with full line highlight)
    if old_count > 0 then
      for i = 0, old_count - 1 do
        local old_line_idx = old_start + i
        if old_line_idx <= #old_lines then
          local line_content = old_lines[old_line_idx]
          -- Place virtual text strategically
          local attach_line = math.max(0, new_start - 1)
          if attach_line >= api.nvim_buf_line_count(self.bufnr) then
            attach_line = api.nvim_buf_line_count(self.bufnr) - 1
          end
          -- Create full-width virtual line
          local padding = math.max(0, vim.o.columns - #line_content - 2) -- Leave some margin
          local extmark_id = api.nvim_buf_set_extmark(self.bufnr, self.ns_id, attach_line, 0, {
            virt_lines = { { { line_content .. string.rep(" ", padding), "DiffDelete" } } },
            virt_lines_above = true,
            priority = 100,
          })
          table.insert(self.extmark_ids, extmark_id)
        end
      end
    end

    -- Handle added/modified lines (highlight in green)
    if new_count > 0 then
      for i = 0, new_count - 1 do
        local new_line_idx = new_start + i - 1 -- Convert to 0-based indexing
        if new_line_idx >= 0 and new_line_idx < api.nvim_buf_line_count(self.bufnr) then
          log:debug("[InlineDiff] Adding green highlight at line %d", new_line_idx)
          local extmark_id = api.nvim_buf_set_extmark(self.bufnr, self.ns_id, new_line_idx, 0, {
            line_hl_group = "DiffAdd",
            priority = 100,
          })
          table.insert(self.extmark_ids, extmark_id)
        end
      end
    end
  end
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
