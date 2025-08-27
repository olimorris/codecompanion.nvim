local diff_utils = require("codecompanion.providers.diff.utils")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local api = vim.api

---@class CodeCompanion.Diff.Inline
---@field bufnr integer
---@field contents string[]
---@field id string
---@field ns_id integer
---@field extmark_ids integer[]
---@field has_changes boolean
local InlineDiff = {}

---@class CodeCompanion.Diff.InlineArgs
---@field bufnr integer Buffer number to apply diff to
---@field contents string[] Original content lines
---@field id string Unique identifier for this diff

---Creates a new InlineDiff instance and applies diff highlights
---@param args CodeCompanion.Diff.InlineArgs
---@return CodeCompanion.Diff.Inline
function InlineDiff.new(args)
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
  ---@cast self CodeCompanion.Diff.Inline

  local current_content = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  if self:contents_equal(self.contents, current_content) then
    log:debug("[providers::diff::inline::new] No changes detected")
    util.fire("DiffAttached", { diff = "inline", bufnr = self.bufnr, id = self.id })
    return self
  end
  log:debug("[providers::diff::inline::new] Changes detected - applying diff highlights")
  self.has_changes = true
  local first_diff_line = self:apply_diff_highlights(self.contents, current_content)
  if first_diff_line then
    vim.schedule(function()
      local winnr = vim.fn.bufwinid(self.bufnr)
      if winnr ~= -1 then
        pcall(api.nvim_win_set_cursor, winnr, { first_diff_line, 0 })

        if vim.api.nvim_get_mode().mode ~= "n" then
          vim.api.nvim_input("<ESC>")
        end
      end
    end)
  end
  util.fire("DiffAttached", { diff = "inline", bufnr = self.bufnr, id = self.id })
  return self
end

---Calculate diff hunks between two content arrays
---@param old_lines string[] Original content
---@param new_lines string[] New content
---@param context_lines? integer Number of context lines (default: 3)
---@return CodeCompanion.Diff.Utils.DiffHunk[] hunks
function InlineDiff.calculate_hunks(old_lines, new_lines, context_lines)
  return diff_utils.calculate_hunks(old_lines, new_lines, context_lines)
end

---Apply visual highlights to hunks in a buffer with sign column indicators
---@param bufnr integer Buffer to apply highlights to
---@param hunks CodeCompanion.Diff.Utils.DiffHunk[] Hunks to highlight
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
---@return integer|nil first_diff_line First line with changes (1-based) for cursor positioning
function InlineDiff:apply_diff_highlights(old_lines, new_lines)
  log:debug("[providers::diff::inline::apply_diff_highlights] Called")
  -- Get inline diff configuration (lazy load to avoid circular dependency)
  local config = require("codecompanion.config")
  local inline_config = config.display and config.display.diff and config.display.diff.inline or {}
  local context_lines = inline_config.context_lines or 3
  local hunks = InlineDiff.calculate_hunks(old_lines, new_lines, context_lines)
  local first_diff_line = nil
  -- Add keymap hint above the first hunk if there are changes
  if #hunks > 0 then
    local first_hunk = hunks[1]
    first_diff_line = math.max(1, first_hunk.new_start) -- Store for cursor positioning
    -- Only show keymap hints if config allows it and not in test mode
    local show_keymap_hints = inline_config.show_keymap_hints
    if show_keymap_hints == nil then
      show_keymap_hints = true -- Default to true
    end
    -- Check if we're in a test environment
    ---@diagnostic disable-next-line: undefined-field
    local is_testing = _G.MiniTest ~= nil
    if show_keymap_hints and not is_testing then
      local attach_line = math.max(0, first_hunk.new_start - 2)
      if first_diff_line == 1 then
        attach_line = attach_line + 1
      end
      -- Build hint text from configured keymaps
      local keymaps_config = config.strategies.inline.keymaps
      if keymaps_config then
        local hint_parts = {}
        table.insert(hint_parts, keymaps_config.accept_change.modes.n .. ": accept")
        table.insert(hint_parts, keymaps_config.reject_change.modes.n .. ": reject")
        table.insert(hint_parts, keymaps_config.always_accept.modes.n .. ": always accept")

        local hint_text = table.concat(hint_parts, " | ")
        local success, keymap_extmark_id = pcall(api.nvim_buf_set_extmark, self.bufnr, self.ns_id, attach_line, 0, {
          virt_text = { { hint_text, "CodeCompanionInlineDiffHint" } },
          virt_text_pos = "right_align",
          priority = 300,
        })
        if not success then
          log:debug("[providers::diff::inline] Failed to create keymap hint: %s", keymap_extmark_id)
        end
        table.insert(self.extmark_ids, keymap_extmark_id)
      end
    end
  end

  local extmark_ids = InlineDiff.apply_hunk_highlights(self.bufnr, hunks, self.ns_id, 0, {
    show_removed = inline_config.show_removed ~= false,
    full_width_removed = inline_config.full_width_removed ~= false,
  })
  vim.list_extend(self.extmark_ids, extmark_ids)
  log:debug(
    "[providers::diff::inline::apply_diff_highlights] Applied %d extmarks for diff visualization",
    #self.extmark_ids
  )

  return first_diff_line
end

---Clears all diff highlights and extmarks
---@return nil
function InlineDiff:clear_highlights()
  if api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_clear_namespace(self.bufnr, self.ns_id, 0, -1)
  end
  self.extmark_ids = {}
end

---Accepts the diff changes and clears highlights
---@return nil
function InlineDiff:accept()
  log:debug("[providers::diff::inline::accept] Called")
  util.fire("DiffAccepted", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = true })
  pcall(function()
    api.nvim_buf_call(self.bufnr, function()
      vim.cmd("silent update")
    end)
  end)
  self:clear_highlights()
end

---Rejects the diff changes, restores original content, and clears highlights
---@return nil
function InlineDiff:reject()
  util.fire("DiffRejected", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = false })
  log:debug("[providers::diff::inline::reject] Called")
  if api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.contents)
  end
  pcall(function()
    api.nvim_buf_call(self.bufnr, function()
      vim.cmd("silent update")
    end)
  end)
  self:clear_highlights()
end

---Cleans up the diff instance and fires detachment event
---@return nil
function InlineDiff:teardown()
  log:debug("[providers::diff::inline::teardown] Called")
  pcall(function()
    api.nvim_buf_call(self.bufnr, function()
      vim.cmd("silent update")
    end)
  end)
  self:clear_highlights()
  util.fire("DiffDetached", { diff = "inline", bufnr = self.bufnr, id = self.id })
end

return InlineDiff
