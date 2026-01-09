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

---Show banner in the diff buffer
---@param bufnr number
---@param opts { banner?: string, current_hunk: number, hunks: number, inline?: boolean, namespace: number, line?: number, overwrite?: boolean }
---@return number The namespace ID used for the banner extmark
local function banner_virt_text(bufnr, opts)
  local ns_id = api.nvim_create_namespace("codecompanion_diff_ui_" .. tostring(opts.namespace))

  if opts.overwrite then
    pcall(api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
  end

  local text = fmt(" [%d/%d]  %s ", opts.current_hunk or 1, opts.hunks or 1, opts.banner or build_default_banner())

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
  end

  -- Always set up navigation keymaps
  local next_hunk_key = config.interactions.inline.keymaps.next_hunk.modes.n
  local prev_hunk_key = config.interactions.inline.keymaps.previous_hunk.modes.n

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

---Apply diff extmarks to a buffer
---@param diff CC.Diff
---@return nil
function DiffUI:apply_extmarks(diff, bufnr)
  local line_count = api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return utils.notify("Cannot apply diff to empty buffer", vim.log.levels.ERROR)
  end

  if diff.should_offset then
    api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
  end

  -- Apply the extmarks
  for _, hunk in ipairs(diff.hunks) do
    for _, extmark in ipairs(hunk.extmarks) do
      local opts = {}
      for k, v in pairs(extmark) do
        if k ~= "row" and k ~= "col" then
          opts[k] = v
        end
      end

      pcall(api.nvim_buf_set_extmark, bufnr, diff.namespace, extmark.row, extmark.col, opts)
    end
  end
end

---Clear diff extmarks from buffer
---@return nil
function DiffUI:clear()
  if self.inline then
    return pcall(api.nvim_buf_clear_namespace, self.bufnr, self.diff.namespace, 0, -1)
  end
end

---Show a diff in a floating window
---@param opts { diff: CC.Diff, cfg: CodeCompanion.WindowOpts, title?: string }
---@return number, number Buffer and window numbers
local function show_in_float(opts)
  return ui_utils.create_float(opts.diff.from.lines, {
    width = opts.cfg.width,
    height = opts.cfg.height,
    row = opts.cfg.row,
    col = opts.cfg.col,
    ft = opts.diff.ft or "text",
    ignore_keymaps = true,
    opts = opts.cfg.opts,
    title = " " .. opts.title or get_buf_name(opts.diff.bufnr) .. " ",
  })
end

---Show a diff in a floating window
---@param diff CC.Diff The diff object from diff.create()
---@param opts? { diff_id?: number, float?: boolean, title?: string, banner?: string, skip_default_keymaps?: boolean, chat_bufnr?: number, tool_name?: string }
---@return CodeCompanion.DiffUI
function M.show(diff, opts)
  opts = vim.tbl_extend("force", { float = true }, opts or {})

  local bufnr
  local winnr
  ---@type CodeCompanion.WindowOpts
  local cfg =
    vim.tbl_deep_extend("force", config.display.chat.floating_window or {}, config.display.chat.diff_window or {})

  if opts.float then
    bufnr, winnr = show_in_float({
      diff = diff,
      cfg = cfg,
      title = opts.title,
    })
  end

  local group = api.nvim_create_augroup("codecompanion.diff_window_" .. bufnr, { clear = true })

  ---@type CodeCompanion.DiffUI
  local diff_ui = setmetatable({
    banner = opts.banner,
    bufnr = bufnr,
    chat_bufnr = opts.chat_bufnr,
    current_hunk = 1,
    diff = diff,
    diff_id = opts.diff_id or math.random(10000000),
    hunks = #diff.hunks,
    inline = opts.inline,
    resolved = false,
    tool_name = opts.tool_name,
    winnr = winnr,
  }, DiffUI)

  DiffUI:apply_extmarks(diff, bufnr)

  local function show_banner(args)
    args = args or {}

    return banner_virt_text(bufnr, {
      banner = opts.banner,
      current_hunk = diff_ui.current_hunk,
      hunks = diff_ui.hunks,
      overwrite = args.overwrite or false,
    })
  end

  -- Lock the buffer so the user can't make any changes
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false

  -- Scroll to first hunk
  if #diff.hunks > 0 then
    vim.schedule(function()
      ui_utils.scroll_to_line(bufnr, diff.hunks[1].pos[1] + 1)
    end)
  end

  -- Show the banner after scrolling to the first hunk
  show_banner()

  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "CodeCompanionDiffHunkChanged",
    group = group,
    callback = function(event)
      if event.data.bufnr ~= bufnr then
        return
      end
      show_banner({ overwrite = true })
    end,
  })
  -- Ensure that the banner always follows the cursor
  api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      show_banner({ overwrite = true })
    end,
  })
  api.nvim_create_autocmd({ "WinClosed", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      pcall(api.nvim_clear_autocmds, { group = group })
    end,
  })

  diff_ui:setup_keymaps({ skip_default_keymaps = opts.skip_default_keymaps or false })

  -- If the user closes a window prematurely then reject the diff
  if not opts.skip_default_keymaps then
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

  return diff_ui
end

return M
