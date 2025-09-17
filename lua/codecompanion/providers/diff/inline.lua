local diff_utils = require("codecompanion.providers.diff.utils")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local api = vim.api

---@class CodeCompanion.Diff.Inline
---@field bufnr number
---@field contents string[]
---@field id number
---@field ns_id number
---@field extmark_ids number[]
---@field has_changes boolean
---@field winnr number|nil
---@field is_floating boolean
local InlineDiff = {}

---@class CodeCompanion.Diff.InlineArgs
---@field bufnr number Buffer number to apply diff to
---@field contents string[] Original content lines
---@field id number|string Unique identifier for this diff
---@field winnr? number Window number (optional)
---@field is_floating boolean|nil Whether this diff is in a floating window

---Creates a new InlineDiff instance and applies diff highlights
---@param args CodeCompanion.Diff.InlineArgs
---@return CodeCompanion.Diff.Inline
function InlineDiff.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    contents = args.contents,
    id = args.id,
    winnr = args.winnr,
    is_floating = args.is_floating or false,
    ns_id = api.nvim_create_namespace(
      "codecompanion_inline_diff_" .. (args.id ~= nil and args.id or math.random(1, 100000))
    ),
    extmark_ids = {},
    has_changes = false,
  }, { __index = InlineDiff })
  ---@cast self CodeCompanion.Diff.Inline

  local current_content = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  if self:contents_equal(self.contents, current_content) then
    log:trace("[providers::diff::inline::new] No changes detected")
    util.fire("DiffAttached", { diff = "inline", bufnr = self.bufnr, id = self.id })
    return self
  end

  self.has_changes = true
  log:trace("[providers::diff::inline::new] Changes detected - applying diff highlights")

  local first_diff_line = self:apply_diff_highlights(self.contents, current_content)
  if first_diff_line then
    vim.schedule(function()
      self.winnr = self.winnr and self.winnr or vim.fn.bufwinid(self.bufnr)
      if self.winnr ~= -1 then
        pcall(api.nvim_win_set_cursor, self.winnr, { first_diff_line, 0 })

        if api.nvim_get_mode().mode ~= "n" then
          api.nvim_input("<ESC>")
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
---@param context_lines? number Number of context lines (default: 3)
---@return CodeCompanion.Diff.Utils.DiffHunk[] hunks
function InlineDiff.calculate_hunks(old_lines, new_lines, context_lines)
  return diff_utils.calculate_hunks(old_lines, new_lines, context_lines)
end

---Apply visual highlights to hunks in a buffer with sign column indicators
---@param bufnr number Buffer to apply highlights to
---@param hunks CodeCompanion.Diff.Utils.DiffHunk[] Hunks to highlight
---@param ns_id number Namespace for extmarks
---@param line_offset? number Line offset
---@param opts? table Options: {show_removed: boolean, full_width_removed: boolean, status?: string}
---@return number[] extmark_ids
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
---@return number|nil first_diff_line First line with changes (1-based) for cursor positioning
function InlineDiff:apply_diff_highlights(old_lines, new_lines)
  log:trace("[providers::diff::inline::apply_diff_highlights] Called")

  -- WARN: We need to lazy load the config here to avoid a circular dependency issue
  local config = require("codecompanion.config")
  local inline_config = config.display.diff.provider_opts.inline
  local context_lines = inline_config.opts.context_lines or 3
  local hunks = InlineDiff.calculate_hunks(old_lines, new_lines, context_lines)
  local first_diff_line = nil

  -- Add keymap hint above the first hunk if there are changes
  if #hunks > 0 then
    local first_hunk = hunks[1]
    first_diff_line = math.max(1, first_hunk.new_start) -- Store for cursor positioning
    -- Only show keymap hints if config allows it, not in test mode, and not floating
    local show_keymap_hints = inline_config.opts.show_keymap_hints
    if show_keymap_hints == nil then
      show_keymap_hints = true -- Default to true
    end
    -- Check if we're in a test environment
    ---@diagnostic disable-next-line: undefined-field
    local is_testing = _G.MiniTest ~= nil
    -- Don't show hints for floating windows since they use winbar instead
    if show_keymap_hints and not is_testing and not self.is_floating then
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
    show_removed = inline_config.opts.show_removed ~= false,
    full_width_removed = inline_config.opts.full_width_removed ~= false,
    is_floating = self.is_floating,
  })
  vim.list_extend(self.extmark_ids, extmark_ids)
  log:trace(
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
---@param opts? table
---@return nil
function InlineDiff:accept(opts)
  opts = opts or {}
  if opts.save == nil then
    opts.save = true
  end

  log:debug("[providers::diff::inline::accept] Called")

  util.fire("DiffAccepted", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = true })
  if opts.save then
    pcall(function()
      api.nvim_buf_call(self.bufnr, function()
        vim.cmd("silent update")
      end)
    end)
  end

  self:clear_highlights()
  self:close_floating_window()
end

---Rejects the diff changes, restores original content, and clears highlights
---@param opts? table
---@return nil
function InlineDiff:reject(opts)
  opts = opts or {}
  if opts.save == nil then
    opts.save = true
  end

  log:debug("[providers::diff::inline::reject] Called")

  util.fire("DiffRejected", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = false })
  if api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.contents)
  end

  if opts.save then
    pcall(function()
      api.nvim_buf_call(self.bufnr, function()
        vim.cmd("silent update")
      end)
    end)
  end

  self:clear_highlights()
  self:close_floating_window()
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
  self:close_floating_window()
  util.fire("DiffDetached", { diff = "inline", bufnr = self.bufnr, id = self.id })
end

---Close floating window if this diff is in a floating window
---@return nil
function InlineDiff:close_floating_window()
  if self.is_floating and self.winnr and api.nvim_win_is_valid(self.winnr) then
    log:debug("[providers::diff::inline::close_floating_window] Closing floating window %d", self.winnr)
    pcall(api.nvim_win_close, self.winnr, true)
    self.winnr = nil
    local ui = require("codecompanion.utils.ui")
    ui.close_background_window()
  end
end

return InlineDiff
