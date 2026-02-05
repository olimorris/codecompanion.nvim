local config = require("codecompanion.config")
local diff_utils = require("codecompanion.diff.utils")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local fmt = string.format
local api = vim.api

local M = {}

---@class CodeCompanion.DiffUI
---@field aug_group? number The autocommand group ID for the banner
---@field banner? string The banner of keymaps to display above each hunk
---@field banner_ns? number The namespace ID for the banner extmark
---@field bufnr number The buffer number of the diff window
---@field chat_bufnr? number If the diff has an associated chat buffer, pass in the chat buffer number
---@field current_hunk number The current hunk index (1-based)
---@field diff CC.Diff
---@field diff_id number
---@field hunks number The total number of hunks in the diff
---@field inline? boolean Whether the diff is shown inline or in a floating window
---@field keymaps table<string, fun(diff_ui: CodeCompanion.DiffUI)> Custom keymap callbacks (on_accept, on_reject, on_always_accept)
---@field ns number The namespace ID for diff extmarks
---@field resolved boolean Whether the diff has been resolved (accepted/rejected)
---@field tool_name? string This is essential for approvals to work with tools
---@field winnr number
local DiffUI = {}
DiffUI.__index = DiffUI

-- Cache for computed values that depend only on config
local _cached_default_banner = nil

---Get the display name for a buffer
---@param bufnr number
---@return string
local function get_buf_name(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  if not name or name ~= "" then
    return vim.fn.fnamemodify(name, ":.")
  end
  return fmt("buffer %d", bufnr)
end

---Build the default keymaps from config for display (cached)
---@return string
local function get_default_banner()
  if _cached_default_banner then
    return _cached_default_banner
  end

  local shared_keymaps = config.interactions.shared.keymaps
  _cached_default_banner = fmt(
    "%s Always Accept | %s Accept | %s Reject | %s/%s Next/Prev hunks | q Close",
    shared_keymaps.always_accept.modes.n,
    shared_keymaps.accept_change.modes.n,
    shared_keymaps.reject_change.modes.n,
    shared_keymaps.next_hunk.modes.n,
    shared_keymaps.previous_hunk.modes.n
  )
  return _cached_default_banner
end

---Get the banner text for display
---@param opts { banner?: string, current_hunk: number, hunks: number }
---@return string
local function build_banner_text(opts)
  return fmt(" [Hunk: %d/%d]  %s ", opts.current_hunk or 1, opts.hunks or 1, opts.banner or get_default_banner())
end

---Show banner in the diff buffer
---@param bufnr number
---@param opts { banner?: string, current_hunk: number, hunks: number, inline?: boolean, namespace: number, line?: number, overwrite?: boolean }
---@return number The namespace ID used for the banner extmark
local function banner_virt_text(bufnr, opts)
  local ns_id = api.nvim_create_namespace("codecompanion_diff_ui_" .. tostring(opts.namespace))

  if opts.overwrite then
    pcall(api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
  end

  local text = build_banner_text(opts)
  local line = opts.line or (vim.fn.line("w0") - 1)

  if opts.inline then
    api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
      virt_lines = { { { text, "CodeCompanionDiffBannerInline" } } },
      virt_lines_above = true,
      priority = 125,
    })
  else
    api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
      virt_text = {
        { text, "CodeCompanionDiffBanner" },
      },
      virt_text_pos = "right_align",
      priority = 125,
    })
  end

  return ns_id
end

---Navigate to next hunk
---@param line number
function DiffUI:next_hunk(line)
  for index, hunk in ipairs(self.diff.hunks) do
    local hunk_line = hunk.pos[1] + 1
    if hunk_line > line then
      self.current_hunk = index
      ui_utils.scroll_to_line(self.bufnr, hunk_line)
      return utils.fire("DiffHunkChanged", { id = self.diff_id, bufnr = self.bufnr })
    end
  end

  -- Wrap around to first hunk
  if #self.diff.hunks > 0 then
    self.current_hunk = 1
    local hunk_line = self.diff.hunks[1].pos[1] + 1
    ui_utils.scroll_to_line(self.bufnr, hunk_line)
    return utils.fire("DiffHunkChanged", { id = self.diff_id, bufnr = self.bufnr })
  end
end

---Navigate to previous hunk
---@param line number
---@return nil
function DiffUI:previous_hunk(line)
  for i = #self.diff.hunks, 1, -1 do
    local hunk = self.diff.hunks[i]
    local hunk_line = hunk.pos[1] + 1
    if hunk_line < line then
      self.current_hunk = i
      ui_utils.scroll_to_line(self.bufnr, hunk_line)
      return utils.fire("DiffHunkChanged", { id = self.diff_id, bufnr = self.bufnr })
    end
  end

  -- Wrap around to last hunk
  if #self.diff.hunks > 0 then
    self.current_hunk = #self.diff.hunks
    local hunk_line = self.diff.hunks[#self.diff.hunks].pos[1] + 1
    ui_utils.scroll_to_line(self.bufnr, hunk_line)
    return utils.fire("DiffHunkChanged", { id = self.diff_id, bufnr = self.bufnr })
  end
end

---Close the diff window
---@return nil
function DiffUI:close()
  if self.inline then
    return
  end
  pcall(api.nvim_win_close, self.winnr, true)
  pcall(api.nvim_buf_delete, self.bufnr, { force = true })
end

---Set a single keymap for the diff buffer
---@param mode string
---@param lhs string
---@param handler { callback: function, desc: string }
---@return nil
function DiffUI:_set_keymap(mode, lhs, handler)
  vim.keymap.set(mode, lhs, function()
    handler.callback(self)
  end, {
    buffer = self.bufnr,
    desc = handler.desc,
    silent = true,
    nowait = true,
  })
end

---Set up keymaps in the diff buffer
---@param opts { skip_default_keymaps?: boolean }
---@return nil
function DiffUI:setup_keymaps(opts)
  opts = opts or {}

  local keymaps = require("codecompanion.diff.keymaps")

  local shared_keymaps = config.interactions.shared.keymaps

  if not opts.skip_default_keymaps then
    for name, keymap in pairs(shared_keymaps) do
      local handler = keymaps[name]
      if handler then
        for mode, lhs in pairs(keymap.modes) do
          self:_set_keymap(mode, lhs, handler)
        end
      end
    end
  else
    -- Provide minimal navigation controls when skipping defaults
    self:_set_keymap("n", shared_keymaps.next_hunk.modes.n, keymaps.next_hunk)
    self:_set_keymap("n", shared_keymaps.previous_hunk.modes.n, keymaps.previous_hunk)
  end

  -- Always add 'q' to close
  self:_set_keymap("n", "q", keymaps.close_window)
end

---Apply diff highlighting to merged lines in a buffer
---@param diff CC.Diff
---@param bufnr number
---@return nil
function DiffUI:apply_extmarks(diff, bufnr)
  local line_count = api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return utils.notify("Cannot apply diff to empty buffer", vim.log.levels.ERROR)
  end

  local word_highlights = config.display.diff.word_highlights
  local show_word_additions = word_highlights.additions ~= false
  local show_word_deletions = word_highlights.deletions ~= false

  -- Apply line highlights from the merged highlights data
  for _, hl in ipairs(diff.merged.highlights) do
    local row = hl.row - 1 -- Convert to 0-indexed

    if row >= 0 and row < line_count then
      local opts = {}

      if hl.type == "deletion" then
        opts.line_hl_group = "CodeCompanionDiffDelete"
        if diff.marker_delete then
          opts.sign_text = diff.marker_delete
          opts.sign_hl_group = "CodeCompanionDiffDelete"
        end
      elseif hl.type == "addition" then
        opts.line_hl_group = "CodeCompanionDiffAdd"
        if diff.marker_add then
          opts.sign_text = diff.marker_add
          opts.sign_hl_group = "CodeCompanionDiffAdd"
        end
      end

      pcall(api.nvim_buf_set_extmark, bufnr, self.ns, row, 0, opts)

      -- Apply word-level highlights using virtual text overlay
      -- This allows word highlights to show background colors over line highlights
      if hl.word_hl and #hl.word_hl > 0 then
        local word_hl_group = hl.type == "deletion" and show_word_deletions and "CodeCompanionDiffTextDelete"
          or hl.type == "addition" and show_word_additions and "CodeCompanionDiffText"
          or nil

        if word_hl_group then
          local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
          for _, range in ipairs(hl.word_hl) do
            local word_text = line:sub(range.col + 1, range.end_col)
            if word_text ~= "" then
              pcall(api.nvim_buf_set_extmark, bufnr, self.ns, row, range.col, {
                virt_text = { { word_text, word_hl_group } },
                virt_text_pos = "overlay",
                hl_mode = "combine",
                priority = 150,
              })
            end
          end
        end
      end
    end
  end
end

---Clear diff extmarks from buffer
---@return nil
function DiffUI:clear()
  if self.aug_group then
    pcall(api.nvim_del_augroup_by_id, self.aug_group)
  end

  if self.banner_ns then
    pcall(api.nvim_buf_clear_namespace, self.bufnr, self.banner_ns, 0, -1)
  end

  if self.inline then
    if self.inline_spacer_mark then
      local pos = api.nvim_buf_get_extmark_by_id(self.bufnr, self.ns, self.inline_spacer_mark, {})
      if pos and pos[1] then
        pcall(api.nvim_buf_set_lines, self.bufnr, pos[1], pos[1] + 1, false, {})
      end
      self.inline_spacer_mark = nil
    end
    return pcall(api.nvim_buf_clear_namespace, self.bufnr, self.ns, 0, -1)
  end
end

---Apply inline diff changes and virtual deletion lines
---@param diff CC.Diff
---@param bufnr number
---@return nil
function DiffUI:apply_inline(diff, bufnr)
  local function slice(lines, start_index, count)
    local out = {}
    for i = 0, count - 1 do
      out[#out + 1] = lines[start_index + i]
    end
    return out
  end

  local line_offset = 0
  for _, hunk in ipairs(diff.hunks) do
    if hunk.from_start == 1 and hunk.from_count > 0 then
      line_offset = 1
      break
    end
  end

  if line_offset > 0 then
    api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
    self.inline_spacer_mark = api.nvim_buf_set_extmark(bufnr, self.ns, 0, 0, {})
  end

  for i = #diff.hunks, 1, -1 do
    local hunk = diff.hunks[i]
    local from_start = hunk.from_start
    local from_count = hunk.from_count
    local to_start = hunk.to_start
    local to_count = hunk.to_count
    local from_index = from_start - 1 + line_offset
    local marker_add = diff.marker_add
    local marker_delete = diff.marker_delete
    if from_count == 0 then
      from_index = from_start + line_offset
    end
    local deleted_lines = {}

    if from_count > 0 then
      deleted_lines = slice(diff.from.lines, from_start, from_count)
      api.nvim_buf_set_lines(bufnr, from_index, from_index + from_count, false, {})
    end

    if to_count > 0 then
      local added_lines = slice(diff.to.lines, to_start, to_count)
      api.nvim_buf_set_lines(bufnr, from_index, from_index, false, added_lines)
      for j = 0, to_count - 1 do
        pcall(api.nvim_buf_set_extmark, bufnr, self.ns, from_index + j, 0, {
          line_hl_group = "CodeCompanionDiffAdd",
          virt_text = marker_add and { { marker_add .. " ", "CodeCompanionDiffAdd" } } or nil,
          virt_text_pos = marker_add and "inline" or nil,
          hl_mode = marker_add and "combine" or nil,
          priority = 150,
        })
      end
    end

    if #deleted_lines > 0 then
      local line_count = api.nvim_buf_line_count(bufnr)
      local anchor_row = 0
      local virt_above = false
      local hl_group = "CodeCompanionDiffDelete"
      if line_count == 0 then
        anchor_row = 0
        virt_above = false
      elseif from_index >= line_count then
        anchor_row = line_count - 1
        virt_above = false
      else
        anchor_row = from_index
        virt_above = true
      end
      local virt_lines = diff_utils.create_vl(table.concat(deleted_lines, "\n"), {
        ft = diff.ft or vim.bo[bufnr].filetype,
        bg = hl_group,
      })
      if marker_delete then
        virt_lines = diff_utils.prepend_marker(virt_lines, marker_delete, hl_group)
      end
      virt_lines = diff_utils.extend_vl(virt_lines, hl_group)

      pcall(api.nvim_buf_set_extmark, bufnr, self.ns, anchor_row, 0, {
        virt_lines = virt_lines,
        virt_lines_above = virt_above,
        hl_mode = "combine",
        priority = 150,
      })
    end
  end

  local line_count = api.nvim_buf_line_count(bufnr)
  for _, hunk in ipairs(diff.hunks) do
    local target_row = (hunk.to_start or 1) - 1 + line_offset
    if line_count > 0 then
      target_row = math.min(math.max(target_row, 0), line_count - 1)
    else
      target_row = 0
    end
    hunk.pos = { target_row, 0 }
  end
end

---Show a diff in a floating window
---@param opts { diff: CC.Diff, cfg: CodeCompanion.WindowOpts, title?: string }
---@return number, number Buffer and window numbers
local function show_in_float(opts)
  return ui_utils.create_float(opts.diff.merged.lines, {
    width = opts.cfg.width,
    height = opts.cfg.height,
    row = opts.cfg.row,
    col = opts.cfg.col,
    ft = opts.diff.ft or "text",
    ignore_keymaps = true,
    opts = opts.cfg.opts,
    title = opts.title or get_buf_name(opts.diff.bufnr),
  })
end

---Create and configure the diff window
---@param diff CC.Diff
---@param opts { cfg: CodeCompanion.WindowOpts, float: boolean, title?: string }
---@return number bufnr
---@return number winnr
local function create_diff_display(diff, opts)
  local bufnr, winnr

  if opts.float then
    bufnr, winnr = show_in_float({
      diff = diff,
      cfg = opts.cfg,
      title = opts.title,
    })
  else
    bufnr = diff.bufnr
    winnr = ui_utils.buf_get_win(bufnr)
    if not winnr or not api.nvim_win_is_valid(winnr) then
      winnr = api.nvim_get_current_win()
      api.nvim_win_set_buf(winnr, bufnr)
    end
  end

  -- Lock the buffer for floating windows
  if opts.float then
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].modifiable = false
  end

  -- Populate buffer if empty
  if ui_utils.buf_is_empty(bufnr) then
    api.nvim_buf_set_lines(bufnr, 0, -1, false, diff.merged.lines)
  end

  return bufnr, winnr
end

---Set up banner display and tracking
---@param diff_ui CodeCompanion.DiffUI
---@param opts { banner?: string, is_float: boolean, inline: boolean }
---@return number group Autocommand group ID
local function setup_banner(diff_ui, opts)
  local bufnr = diff_ui.bufnr
  local group = api.nvim_create_augroup("codecompanion.diff_window_" .. bufnr, { clear = true })
  diff_ui.aug_group = group

  local function show_banner(args)
    args = args or {}

    if opts.is_float then
      local text = build_banner_text({
        banner = opts.banner,
        current_hunk = diff_ui.current_hunk,
        hunks = diff_ui.hunks,
      })
      return ui_utils.set_winbar(diff_ui.winnr, text, "CodeCompanionDiffBanner")
    end

    local hunk = diff_ui.diff.hunks[diff_ui.current_hunk]
    local target_line = opts.inline and hunk and hunk.pos[1] or nil

    local ns_id = banner_virt_text(bufnr, {
      banner = opts.banner,
      current_hunk = diff_ui.current_hunk,
      hunks = diff_ui.hunks,
      inline = true,
      line = target_line,
      namespace = diff_ui.diff_id,
      overwrite = args.overwrite or false,
    })

    -- Store the banner namespace for cleanup
    diff_ui.banner_ns = ns_id
    return ns_id
  end

  -- Initial banner
  show_banner()

  -- Track hunk changes
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionDiffHunkChanged",
    group = group,
    callback = function(event)
      if event.data.bufnr ~= bufnr then
        return
      end
      show_banner({ overwrite = true })
    end,
  })

  -- Track window scrolling for inline banners
  if not opts.is_float then
    api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        show_banner({ overwrite = true })
      end,
    })
  end

  return group
end

---Set up window close handler
---@param diff_ui CodeCompanion.DiffUI
---@param group number Autocommand group ID
---@param skip_default_keymaps boolean
local function setup_close_handler(diff_ui, group, skip_default_keymaps)
  local bufnr = diff_ui.bufnr

  -- Clean up on window/buffer close
  api.nvim_create_autocmd({ "WinClosed", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      pcall(api.nvim_clear_autocmds, { group = group })
    end,
  })

  -- Auto-reject on premature close (only if using default keymaps)
  if not skip_default_keymaps then
    vim.api.nvim_clear_autocmds({ buffer = bufnr, event = "WinClosed" })
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      buffer = bufnr,
      once = true,
      callback = function()
        require("codecompanion.diff.keymaps").close_window.callback(diff_ui)
      end,
    })
  end
end

---@class CodeCompanion.DiffUIOptions
---@field chat_bufnr? number
---@field banner? string
---@field diff_id? number
---@field float? boolean
---@field inline? boolean
---@field keymaps.on_always_accept? fun(diff_ui: CodeCompanion.DiffUI)
---@field keymaps.on_accept? fun(diff_ui: CodeCompanion.DiffUI)
---@field keymaps.on_reject? fun(diff_ui: CodeCompanion.DiffUI)
---@field skip_default_keymaps? boolean
---@field title? string
---@field tool_name? string

---Show a diff in a floating window
---@param diff CC.Diff The diff object from diff.create()
---@param opts? CodeCompanion.DiffUIOptions
---@return CodeCompanion.DiffUI
function M.show(diff, opts)
  opts = vim.tbl_extend("force", { float = true }, opts or {})

  local is_inline = opts.inline == true
  local is_float = opts.float ~= false and not is_inline
  local cfg = vim.tbl_deep_extend("force", config.display.chat.floating_window or {}, config.display.diff.window or {})

  -- Create window or inline display
  local bufnr, winnr = create_diff_display(diff, {
    float = is_float,
    title = opts.title,
    cfg = cfg,
  })

  local diff_id = opts.diff_id or math.random(10000000)

  -- Create diff UI object
  ---@type CodeCompanion.DiffUI
  local diff_ui = setmetatable({
    banner = opts.banner,
    bufnr = bufnr,
    chat_bufnr = opts.chat_bufnr,
    current_hunk = 1,
    diff = diff,
    diff_id = diff_id,
    hunks = #diff.hunks,
    inline = opts.inline or not is_float,
    keymaps = opts.keymaps or {},
    ns = api.nvim_create_namespace("codecompanion_diff_extmarks_" .. tostring(diff_id)),
    resolved = false,
    tool_name = opts.tool_name,
    winnr = winnr,
  }, DiffUI)

  if is_inline then
    diff_ui:apply_inline(diff, bufnr)
  else
    diff_ui:apply_extmarks(diff, bufnr)
  end
  diff_ui:setup_keymaps({ skip_default_keymaps = opts.skip_default_keymaps or false })

  -- Scroll to first hunk
  if #diff.hunks > 0 then
    vim.schedule(function()
      ui_utils.scroll_to_line(bufnr, diff.hunks[1].pos[1] + 1)
    end)
  end

  local group = setup_banner(diff_ui, {
    banner = opts.banner,
    is_float = is_float,
    inline = is_inline,
  })

  setup_close_handler(diff_ui, group, opts.skip_default_keymaps or false)

  return diff_ui
end

return M
