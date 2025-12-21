local diff_utils = require("codecompanion.providers.diff.utils")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api

local CONSTANTS = {
  PRIORITY_KEYMAP_HINT = 300,

  ALWAYS_ACCEPT = "always_accept",
  ACCEPT = "accept",
  REJECT = "reject",
}

---@class CodeCompanion.Diff.Inline
---@field bufnr number
---@field contents string[]
---@field extmark_ids number[]
---@field has_changes boolean
---@field id number
---@field is_floating boolean
---@field ns_id number
---@field show_hints boolean
---@field winnr number|nil
---@field winbar {content: string, winhighlight: string}|nil Original winbar state

---@class CodeCompanion.Diff.Inline
local InlineDiff = {}

---@class CodeCompanion.Diff.InlineArgs
---@field bufnr number Buffer number to apply diff to
---@field contents string[] Original content lines
---@field id number|string Unique identifier for this diff
---@field is_floating boolean|nil Whether this diff is in a floating window
---@field show_hints? boolean Whether to show keymap hints (default: true)
---@field winnr? number Window number (optional)

---Creates a new InlineDiff instance and applies diff highlights
---@param args CodeCompanion.Diff.InlineArgs
---@return CodeCompanion.Diff.Inline
function InlineDiff.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    contents = args.contents,
    extmark_ids = {},
    has_changes = false,
    id = args.id,
    is_floating = args.is_floating or false,
    ns_id = api.nvim_create_namespace(
      "codecompanion_inline_diff_" .. (args.id ~= nil and args.id or math.random(1, 100000))
    ),
    show_hints = args.show_hints == nil and true or args.show_hints,
    winnr = args.winnr,
    winbar = {
      content = vim.wo[args.winnr or 0].winbar or "",
      winhighlight = vim.wo[args.winnr or 0].winhighlight or "",
    },
  }, { __index = InlineDiff })
  ---@cast self CodeCompanion.Diff.Inline

  local current_content = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  if self:is_equal(self.contents, current_content) then
    log:trace("[providers::diff::inline::new] No changes detected")
    utils.fire("DiffAttached", { diff = "inline", bufnr = self.bufnr, id = self.id })
    return self
  end

  self.has_changes = true
  log:trace("[providers::diff::inline::new] Changes detected - applying diff highlights")

  local first_diff_line = self:_apply_diff_highlights(self.contents, current_content)
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

  utils.fire("DiffAttached", { diff = "inline", bufnr = self.bufnr, id = self.id })

  return self
end

---Add keymap hint extmark above the first hunk
---@param first_hunk CodeCompanion.Diff.Utils.DiffHunk First diff hunk
---@param inline_config table Inline diff configuration
---@return nil
function InlineDiff:_add_keymap_hint(first_hunk, inline_config)
  local show_keymap_hints = inline_config.opts.show_keymap_hints
  if show_keymap_hints == nil then
    show_keymap_hints = true
  end

  ---@diagnostic disable-next-line: undefined-field
  local is_testing = _G.MiniTest ~= nil
  if not show_keymap_hints or is_testing or self.is_floating or not self.show_hints then
    return
  end

  local first_diff_line = math.max(1, first_hunk.updated_start)
  local attach_line = math.max(0, first_hunk.updated_start - 2)
  if first_diff_line == 1 then
    attach_line = attach_line + 1
  end

  -- Build hint text from configured keymaps
  local config = require("codecompanion.config")
  local keymaps_config = config.interactions.inline.keymaps
  if not keymaps_config then
    return
  end

  local hint_parts = {}
  table.insert(hint_parts, keymaps_config.always_accept.modes.n .. ": " .. CONSTANTS.ALWAYS_ACCEPT)
  table.insert(hint_parts, keymaps_config.accept_change.modes.n .. ": " .. CONSTANTS.ACCEPT)
  table.insert(hint_parts, keymaps_config.reject_change.modes.n .. ": " .. CONSTANTS.REJECT)
  local hint_text = table.concat(hint_parts, " | ")

  local success, keymap_extmark_id = pcall(api.nvim_buf_set_extmark, self.bufnr, self.ns_id, attach_line, 0, {
    virt_text = { { hint_text, "CodeCompanionInlineDiffHint" } },
    virt_text_pos = "right_align",
    priority = CONSTANTS.PRIORITY_KEYMAP_HINT,
  })
  if success then
    table.insert(self.extmark_ids, keymap_extmark_id)
  else
    log:debug("[providers::diff::inline] Failed to create keymap hint: %s", keymap_extmark_id)
  end
end

---Apply diff highlights to this instance
---@param old_lines string[]
---@param new_lines string[]
---@return number|nil first_diff_line First line with changes (1-based) for cursor positioning
function InlineDiff:_apply_diff_highlights(old_lines, new_lines)
  log:trace("[providers::diff::inline::apply_diff_highlights] Called")

  -- WARN: We need to lazy load the config here to avoid a circular dependency issue
  local config = require("codecompanion.config")
  local inline_config = config.display.diff.provider_opts.inline
  local opts_config = inline_config.opts
  local context_lines = opts_config.context_lines or 3
  local hunks = InlineDiff.calculate_hunks({
    old_lines = old_lines,
    new_lines = new_lines,
    context_lines = context_lines,
  })
  local first_diff_line = nil

  -- Add keymap hint above the first hunk if there are changes
  if #hunks > 0 then
    local first_hunk = hunks[1]
    first_diff_line = math.max(1, first_hunk.updated_start) -- Store for cursor positioning
    self:_add_keymap_hint(first_hunk, inline_config)
  end

  local extmark_ids = InlineDiff.apply_hunk_highlights({
    bufnr = self.bufnr,
    hunks = hunks,
    line_offset = 0,
    ns_id = self.ns_id,
    opts = {
      full_width_removed = opts_config.full_width_removed ~= false,
      is_floating = self.is_floating,
      show_removed = opts_config.show_removed ~= false,
    },
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
function InlineDiff:_clear_highlights()
  if api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_clear_namespace(self.bufnr, self.ns_id, 0, -1)
  end
  self.extmark_ids = {}
end

---Clear winbar and winhighlight from the diff window
---@return nil
function InlineDiff:_restore_winbar()
  if self.winnr and api.nvim_win_is_valid(self.winnr) then
    pcall(function()
      vim.wo[self.winnr].winbar = self.winbar.content
      vim.wo[self.winnr].winhighlight = self.winbar.winhighlight
    end)
  end
end

---Close floating window if this diff is in a floating window
---@return nil
function InlineDiff:_close_floating_window()
  if self.is_floating and self.winnr and api.nvim_win_is_valid(self.winnr) then
    log:debug("[providers::diff::inline::close_floating_window] Closing floating window %d", self.winnr)
    pcall(api.nvim_win_close, self.winnr, true)
    self.winnr = nil
    require("codecompanion.utils.ui").close_background_window()
  end
end

---Compares two content arrays for equality
---@param content1 string[] First content array
---@param content2 string[] Second content array
---@return boolean equal True if contents are identical
function InlineDiff:is_equal(content1, content2)
  return diff_utils.is_equal(content1, content2)
end

---Apply visual highlights to hunks in a buffer with sign column indicators
---@param args { bufnr: number, hunks: CodeCompanion.Diff.Utils.DiffHunk[], line_offset?: number, ns_id: number, opts?: table }
---@return number[] extmark_ids
function InlineDiff.apply_hunk_highlights(args)
  return diff_utils.apply_hunk_highlights({
    bufnr = args.bufnr,
    hunks = args.hunks,
    line_offset = args.line_offset,
    ns_id = args.ns_id,
    opts = args.opts,
  })
end

---Calculate diff hunks between two content arrays
---@param args { context_lines?: number, new_lines: string[], old_lines: string[] }
---@return CodeCompanion.Diff.Utils.DiffHunk[] hunks
function InlineDiff.calculate_hunks(args)
  return diff_utils.calculate_hunks({
    added_lines = args.new_lines,
    context_lines = args.context_lines,
    removed_lines = args.old_lines,
  })
end

---Accepts the diff changes and clears highlights
---@param opts? { save: boolean }
---@return nil
function InlineDiff:accept(opts)
  opts = opts or {}
  if opts.save == nil then
    opts.save = true
  end

  log:debug("[providers::diff::inline::accept] Called")

  utils.fire("DiffAccepted", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = true })
  if opts.save then
    pcall(function()
      api.nvim_buf_call(self.bufnr, function()
        vim.cmd("silent update")
      end)
    end)
  end

  self:teardown()
end

---Rejects the diff changes, restores original content, and clears highlights
---@param opts? { save: boolean }
---@return nil
function InlineDiff:reject(opts)
  opts = opts or {}
  if opts.save == nil then
    opts.save = true
  end

  log:debug("[providers::diff::inline::reject] Called")

  utils.fire("DiffRejected", { diff = "inline", bufnr = self.bufnr, id = self.id, accept = false })
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

  self:teardown()
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
  self:_clear_highlights()
  self:_restore_winbar()
  self:_close_floating_window()
  utils.fire("DiffDetached", { diff = "inline", bufnr = self.bufnr, id = self.id })
end

return InlineDiff
