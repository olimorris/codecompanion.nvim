local config = require("codecompanion.config")
local keymaps = require("codecompanion.diff.keymaps")
local ui_utils = require("codecompanion.utils.ui")

local api = vim.api

local M = {}

---@class CodeCompanion.DiffUI
---@field diff CC.Diff
---@field diff_id number
---@field bufnr number
---@field winnr number
---@field chat_bufnr? number If the diff has an associated chat buffer, pass in the chat buffer number
---@field tool_name? string If the diff is associated with a tool, pass in the tool name
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

---Show instructions for diff interaction
---@param bufnr number
---@param namespace number
---@return nil
local function show_keymaps(bufnr, namespace)
  local always_accept = config.interactions.inline.keymaps.always_accept.modes.n
  local accept = config.interactions.inline.keymaps.accept_change.modes.n
  local reject = config.interactions.inline.keymaps.reject_change.modes.n
  local next_hunk = config.interactions.inline.keymaps.next_hunk.modes.n
  local previous_hunk = config.interactions.inline.keymaps.previous_hunk.modes.n

  ui_utils.show_buffer_notification(bufnr, {
    text = string.format(
      "[%s] Always Accept | [%s] Accept | [%s] Reject | [%s]/[%s] Next/Prev hunks | [q] Close",
      always_accept,
      accept,
      reject,
      next_hunk,
      previous_hunk
    ),
    main_hl = "CodeCompanionChatSubtext",
    line = 0,
    namespace = "codecompanion_diff_ui_" .. namespace,
  })
end

---Navigate to next hunk
---@param line number
function DiffUI:next_hunk(line)
  for _, hunk in ipairs(self.diff.hunks) do
    local hunk_line = hunk.pos[1] + 1
    if hunk_line > line then
      return ui_utils.scroll_to_line(self.bufnr, hunk_line)
    end
  end

  if #self.diff.hunks > 0 then
    ui_utils.scroll_to_line(self.bufnr, self.diff.hunks[1].pos[1] + 1)
  end
end

---Navigate to previous hunk
---@param line number
---@return nil
function DiffUI:prev_hunk(line)
  for i = #self.diff.hunks, 1, -1 do
    local hunk = self.diff.hunks[i]
    local hunk_line = hunk.pos[1] + 1
    if hunk_line < line then
      return ui_utils.scroll_to_line(self.bufnr, hunk_line)
    end
  end

  if #self.diff.hunks > 0 then
    ui_utils.scroll_to_line(self.bufnr, self.diff.hunks[#self.diff.hunks].pos[1] + 1)
  end
end

---Close the diff window
---@return nil
function DiffUI:close()
  pcall(api.nvim_win_close, self.winnr, true)
  pcall(api.nvim_buf_delete, self.bufnr, { force = true })
end

---Set up keymaps in the diff buffer
---@return nil
function DiffUI:setup_keymaps()
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

  -- Add 'q' to close
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
---@param opts? { diff_id: number, title?: string, width?: number, height?: number, chat_bufnr?: number, tool_name?: string }
---@return CodeCompanion.DiffUI
function M.show(diff, opts)
  opts = opts or {}

  local cfg = vim.tbl_deep_extend("force", config.display.chat.floating_window, config.display.chat.diff_window or {})

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
    title = opts.title or get_buf_name(diff.bufnr),
  })

  -- Apply diff extmarks
  local Diff = require("codecompanion.diff")
  Diff.apply(diff, bufnr)
  show_keymaps(bufnr, diff.namespace)

  -- Lock the buffer so the user can't make any changes
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false

  ---@type CodeCompanion.DiffUI
  local diff_ui = setmetatable({
    diff = diff,
    diff_id = opts.diff_id or math.random(10000000),
    bufnr = bufnr,
    winnr = winnr,
    chat_bufnr = opts.chat_bufnr,
    tool_name = opts.tool_name,
  }, DiffUI)

  diff_ui:setup_keymaps()

  -- If the user closes a window prematurely then reject the diff
  api.nvim_create_autocmd("WinClosed", {
    buffer = bufnr,
    once = true,
    callback = function()
      keymaps.close_window.callback(diff_ui)
    end,
  })

  -- Scroll to first hunk
  if #diff.hunks > 0 then
    vim.schedule(function()
      ui_utils.scroll_to_line(bufnr, diff.hunks[1].pos[1] + 1)
    end)
  end

  return diff_ui
end

return M
