-- Taken from the awesome:
-- https://github.com/S1M0N38/dante.nvim
local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

---@type table
local Diff

---Accept the diff
---@return nil
function M.accept()
  api.nvim_win_close(Diff.winnr_diff, false)
end

---Reject the diff
---@return nil
function M.reject()
  vim.cmd("diffoff")
  api.nvim_win_close(Diff.winnr_diff, false)

  -- Set the buffer back to the original content
  api.nvim_buf_set_lines(Diff.bufnr, 0, -1, true, Diff.lines)
end

---Setup the provider
---@param opts table {bufnr: number, cursor_pos: number[], filetype: string, lines: string[], winnr: number}
---@return nil
function M.setup(opts)
  Diff = opts
  log:trace("Using default diff")

  -- Get current window properties
  local wrap = vim.wo.wrap
  local linebreak = vim.wo.linebreak
  local breakindent = vim.wo.breakindent
  vim.cmd("set diffopt=" .. table.concat(config.display.inline.diff.opts, ","))

  --- Minimize the chat buffer window if there's not enough screen estate
  local last_chat = require("codecompanion").last_chat()
  if last_chat and last_chat:is_visible() and config.display.inline.diff.close_chat_at > vim.o.columns then
    last_chat:hide()
  end

  -- Create the diff buffer
  if config.display.inline.diff.layout == "vertical" then
    vim.cmd("vsplit")
  else
    vim.cmd("split")
  end
  Diff.winnr_diff = api.nvim_get_current_win()
  Diff.bufnr_diff = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(Diff.winnr_diff, Diff.bufnr_diff)
  api.nvim_set_option_value("filetype", Diff.filetype, { buf = Diff.bufnr_diff })
  api.nvim_set_option_value("wrap", wrap, { win = Diff.winnr_diff })
  api.nvim_set_option_value("linebreak", linebreak, { win = Diff.winnr_diff })
  api.nvim_set_option_value("breakindent", breakindent, { win = Diff.winnr_diff })

  -- Set the diff buffer to the contents, prior to any modifications
  api.nvim_buf_set_lines(Diff.bufnr_diff, 0, 0, true, Diff.lines)
  api.nvim_win_set_cursor(Diff.winnr_diff, { Diff.cursor_pos[1], Diff.cursor_pos[2] })

  -- Begin diffing
  api.nvim_set_current_win(Diff.winnr_diff)
  vim.cmd("diffthis")
  api.nvim_set_current_win(Diff.winnr)
  vim.cmd("diffthis")
end

return M
