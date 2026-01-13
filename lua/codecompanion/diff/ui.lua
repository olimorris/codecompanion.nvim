local config = require("codecompanion.config")
local keymaps = require("codecompanion.diff.keymaps")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local fmt = string.format
local api = vim.api

local M = {}

---@class CodeCompanion.DiffUI
---@field banner? string The banner of keymaps to display above each hunk
---@field bufnr number The buffer number of the diff window
---@field chat_bufnr? number If the diff has an associated chat buffer, pass in the chat buffer number
---@field current_hunk number The current hunk index (1-based)
---@field diff CC.Diff
---@field diff_id number
---@field hunks number The total number of hunks in the diff
---@field inline? boolean Whether the diff is shown inline or in a floating window
---@field ns number The namespace ID for diff extmarks
---@field resolved boolean Whether the diff has been resolved (accepted/rejected)
---@field tool_name? string This is essential for approvals to work with tools
---@field winnr number
local DiffUI = {}
DiffUI.__index = DiffUI

---Get the display name for a buffer
---@param bufnr number
---@return string
local function get_buf_name(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  if name ~= "" then
    return vim.fn.fnamemodify(name, ":.")
  end
  return fmt("buffer %d", bufnr)
end

---Build the default keymaps from config for display
---@return string
local function build_default_banner()
  local always_accept = config.interactions.inline.keymaps.always_accept.modes.n
  local accept = config.interactions.inline.keymaps.accept_change.modes.n
  local reject = config.interactions.inline.keymaps.reject_change.modes.n
  local next_hunk = config.interactions.inline.keymaps.next_hunk.modes.n
  local previous_hunk = config.interactions.inline.keymaps.previous_hunk.modes.n

  return fmt(
    "%s Always Accept | %s Accept | %s Reject | %s/%s Next/Prev hunks | q Close",
    always_accept,
    accept,
    reject,
    next_hunk,
    previous_hunk
  )
end

---Resolve word highlight options from config
---@return { additions: boolean, deletions: boolean }
local function resolve_word_highlights()
  local word_highlights = config.display.diff.word_highlights
  if type(word_highlights) == "table" then
    return {
      additions = word_highlights.additions ~= false,
      deletions = word_highlights.deletions ~= false,
    }
  end

  if word_highlights == true then
    return { additions = true, deletions = true }
  end

  return { additions = false, deletions = false }
end

---Get the banner text for display
---@param opts { banner?: string, current_hunk: number, hunks: number }
---@return string
local function build_banner_text(opts)
  return fmt(" [Hunk: %d/%d]  %s ", opts.current_hunk or 1, opts.hunks or 1, opts.banner or build_default_banner())
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

  api.nvim_buf_set_extmark(bufnr, ns_id, vim.fn.line("w0") - 1, 0, {
    virt_text = {
      { text, opts.inline and "CodeCompanionDiffHintInline" or "CodeCompanionDiffHint" },
    },
    virt_text_pos = "right_align",
    priority = 125,
  })

  return ns_id
end

---Navigate to next hunk
---@param line number
function DiffUI:next_hunk(line)
  if self.hunks == 1 then
    return
  end

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
  if self.hunks == 1 then
    return
  end

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

---Set up keymaps in the diff buffer
---@param opts { skip_default_keymaps?: boolean }
---@return nil
function DiffUI:setup_keymaps(opts)
  opts = opts or {}

  local next_hunk_key = config.interactions.inline.keymaps.next_hunk.modes.n
  local prev_hunk_key = config.interactions.inline.keymaps.previous_hunk.modes.n

  if not opts.skip_default_keymaps then
    local diff_keymaps = config.interactions.inline.keymaps
    for name, keymap in pairs(diff_keymaps) do
      local handler = keymaps[name]
      if handler then
        for mode, lhs in pairs(keymap.modes) do
          vim.keymap.set(mode, lhs, function()
            handler.callback(self)
          end, {
            buffer = self.bufnr,
            desc = handler.desc,
            silent = true,
            nowait = true,
          })
        end
      end
    end
  else
    -- Provide minimal navigation controls when skipping defaults
    vim.keymap.set("n", next_hunk_key, function()
      keymaps.next_hunk.callback(self)
    end, {
      buffer = self.bufnr,
      desc = "Next hunk",
      silent = true,
      nowait = true,
    })

    vim.keymap.set("n", prev_hunk_key, function()
      keymaps.previous_hunk.callback(self)
    end, {
      buffer = self.bufnr,
      desc = "Previous hunk",
      silent = true,
      nowait = true,
    })
  end

  -- Always add 'q' to close
  vim.keymap.set("n", "q", function()
    keymaps.close_window.callback(self)
  end, {
    buffer = self.bufnr,
    desc = "Close and reject",
    silent = true,
    nowait = true,
  })
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

  local word_highlights = resolve_word_highlights()

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

      -- Apply word-level highlights if available
      if hl.word_hl and #hl.word_hl > 0 then
        local word_hl_group = hl.type == "deletion" and word_highlights.deletions and "CodeCompanionDiffDeleteWord"
          or hl.type == "addition" and word_highlights.additions and "CodeCompanionDiffAddWord"
          or nil

        if word_hl_group then
          for _, range in ipairs(hl.word_hl) do
            pcall(api.nvim_buf_set_extmark, bufnr, self.ns, row, range.col, {
              end_col = range.end_col,
              hl_group = word_hl_group,
              priority = 200,
            })
          end
        end
      end
    end
  end
end

---Clear diff extmarks from buffer
---@return nil
function DiffUI:clear()
  if self.inline then
    return pcall(api.nvim_buf_clear_namespace, self.bufnr, self.ns, 0, -1)
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
---@param opts { float: boolean, title?: string, cfg: CodeCompanion.WindowOpts }
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
---@param opts { banner?: string, is_float: boolean }
---@return number group Autocommand group ID
local function setup_banner(diff_ui, opts)
  local bufnr = diff_ui.bufnr
  local group = api.nvim_create_augroup("codecompanion.diff_window_" .. bufnr, { clear = true })

  local function show_banner(args)
    args = args or {}

    if opts.is_float then
      local text = build_banner_text({
        banner = opts.banner,
        current_hunk = diff_ui.current_hunk,
        hunks = diff_ui.hunks,
      })
      return ui_utils.set_winbar(diff_ui.winnr, text, "CodeCompanionDiffHint")
    end

    return banner_virt_text(bufnr, {
      banner = opts.banner,
      current_hunk = diff_ui.current_hunk,
      hunks = diff_ui.hunks,
      inline = true,
      namespace = diff_ui.diff_id,
      overwrite = args.overwrite or false,
    })
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
        keymaps.close_window.callback(diff_ui)
      end,
    })
  end
end

---Show a diff in a floating window
---@param diff CC.Diff The diff object from diff.create()
---@param opts? { diff_id?: number, float?: boolean, title?: string, banner?: string, skip_default_keymaps?: boolean, chat_bufnr?: number, tool_name?: string }
---@return CodeCompanion.DiffUI
function M.show(diff, opts)
  opts = vim.tbl_extend("force", { float = true }, opts or {})

  local is_float = opts.float ~= false
  local cfg =
    vim.tbl_deep_extend("force", config.display.chat.floating_window or {}, config.display.chat.diff_window or {})

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
    ns = api.nvim_create_namespace("codecompanion_diff_extmarks_" .. tostring(diff_id)),
    resolved = false,
    tool_name = opts.tool_name,
    winnr = winnr,
  }, DiffUI)

  diff_ui:apply_extmarks(diff, bufnr)
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
  })

  setup_close_handler(diff_ui, group, opts.skip_default_keymaps or false)

  return diff_ui
end

return M
