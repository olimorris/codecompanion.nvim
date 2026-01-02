local config = require("codecompanion.config")
local keymaps = require("codecompanion.diff.keymaps")
local ui_utils = require("codecompanion.utils.ui")

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
---@field resolved boolean Whether the diff has been resolved (accepted/rejected)
---@field tool_name? string If the diff is associated with a tool, pass in the tool name
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
  return string.format("buffer %d", bufnr)
end

---Build the default keymaps from config for display
---@return string
local function build_default_banner()
  local always_accept = config.interactions.inline.keymaps.always_accept.modes.n
  local accept = config.interactions.inline.keymaps.accept_change.modes.n
  local reject = config.interactions.inline.keymaps.reject_change.modes.n
  local next_hunk = config.interactions.inline.keymaps.next_hunk.modes.n
  local previous_hunk = config.interactions.inline.keymaps.previous_hunk.modes.n

  return string.format(
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
---@param opts { banner?: string, current_hunk: number, hunks: number, namespace: number, line?: number, overwrite?: boolean }
---@return nil
local function show_banner(bufnr, opts)
  local namespace = "codecompanion_diff_ui_" .. tostring(opts.namespace)

  if opts.overwrite then
    ui_utils.clear_notification(bufnr, { namespace = namespace })
  end

  local banner = opts.banner or build_default_banner()

  ui_utils.show_buffer_notification(bufnr, {
    text = string.format("[%d/%d]  %s", opts.current_hunk or 1, opts.hunks or 1, banner),
    main_hl = "CodeCompanionChatSubtext",
    line = opts.line or 0,
    namespace = namespace,
  })
end

---Show banner for the current hunk
---@param hunk number
---@return nil
function DiffUI:show_banner(hunk)
  show_banner(self.bufnr, {
    banner = self.banner,
    current_hunk = self.current_hunk,
    hunks = self.hunks,
    overwrite = true,
    namespace = self.diff.namespace,
    line = hunk,
  })
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
      self:show_banner(hunk_line - 2)
      return ui_utils.scroll_to_line(self.bufnr, hunk_line)
    end
  end

  -- Wrap around to first hunk
  if #self.diff.hunks > 0 then
    self.current_hunk = 1
    local hunk_line = self.diff.hunks[1].pos[1] + 1
    self:show_banner(hunk_line - 2)
    ui_utils.scroll_to_line(self.bufnr, hunk_line)
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
      self:show_banner(hunk_line - 2)
      return ui_utils.scroll_to_line(self.bufnr, hunk_line)
    end
  end

  -- Wrap around to last hunk
  if #self.diff.hunks > 0 then
    self.current_hunk = #self.diff.hunks
    local hunk_line = self.diff.hunks[#self.diff.hunks].pos[1] + 1
    self:show_banner(hunk_line - 2)
    ui_utils.scroll_to_line(self.bufnr, hunk_line)
  end
end

---Close the diff window
---@return nil
function DiffUI:close()
  pcall(api.nvim_win_close, self.winnr, true)
  pcall(api.nvim_buf_delete, self.bufnr, { force = true })
end

---Set up keymaps in the diff buffer
---@param opts { skip_action_keymaps?: boolean }
---@return nil
function DiffUI:setup_keymaps(opts)
  opts = opts or {}
  if not opts.skip_action_keymaps then
    -- Set up default action keymaps from config
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

---Show a diff in a floating window
---@param diff CC.Diff The diff object from diff.create()
---@param opts? { diff_id?: number, title?: string, banner?: string, skip_action_keymaps?: boolean, chat_bufnr?: number, tool_name?: string }
---@return CodeCompanion.DiffUI
function M.show(diff, opts)
  opts = opts or {}

  local cfg =
    vim.tbl_deep_extend("force", config.display.chat.floating_window or {}, config.display.chat.diff_window or {})

  local title = opts.title or get_buf_name(diff.bufnr)

  local bufnr, winnr = ui_utils.create_float(diff.to.lines, {
    window = {
      width = cfg.width,
      height = cfg.height,
      opts = cfg.opts,
    },
    row = cfg.row,
    col = cfg.col,
    filetype = diff.ft or "text",
    ignore_keymaps = true,
    title = " " .. title .. " ",
  })

  ---@type CodeCompanion.DiffUI
  local diff_ui = setmetatable({
    banner = opts.banner,
    bufnr = bufnr,
    chat_bufnr = opts.chat_bufnr,
    current_hunk = 1,
    diff = diff,
    diff_id = opts.diff_id or math.random(10000000),
    hunks = #diff.hunks,
    tool_name = opts.tool_name,
    resolved = false,
    winnr = winnr,
  }, DiffUI)

  -- Apply diff extmarks
  local Diff = require("codecompanion.diff")
  Diff.apply(diff, bufnr)
  show_banner(bufnr, {
    banner = opts.banner,
    current_hunk = 1,
    hunks = #diff.hunks,
    namespace = diff.namespace,
  })

  -- Lock the buffer so the user can't make any changes
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false

  diff_ui:setup_keymaps({ skip_action_keymaps = opts.skip_action_keymaps or false })

  -- If the user closes a window prematurely then reject the diff
  if not opts.skip_action_keymaps then
    vim.api.nvim_clear_autocmds({ buffer = bufnr, event = "WinClosed" })
    api.nvim_create_autocmd("WinClosed", {
      buffer = bufnr,
      once = true,
      callback = function()
        keymaps.close_window.callback(diff_ui)
      end,
    })
  end

  -- Scroll to first hunk
  if #diff.hunks > 0 then
    vim.schedule(function()
      ui_utils.scroll_to_line(bufnr, diff.hunks[1].pos[1] + 1)
    end)
  end

  return diff_ui
end

return M
