-- Taken from the awesome:
-- https://github.com/S1M0N38/dante.nvim

local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

local api = vim.api

---@class CodeCompanion.Diff
---@field bufnr number The buffer number of the original buffer
---@field cursor_pos number[] The position of the cursor in the original buffer
---@field filetype string The filetype of the original buffer
---@field contents string[] The contents of the original buffer
---@field winnr number The window number of the original buffer
---@field diff table The table containing the diff buffer and window
local Diff = {}

---@class CodeCompanion.DiffArgs
---@field bufnr number
---@field cursor_pos? number[]
---@field filetype string
---@field contents string[]
---@field winnr number

---@param args CodeCompanion.DiffArgs
---@return CodeCompanion.Diff
function Diff.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    contents = args.contents,
    cursor_pos = args.cursor_pos or nil,
    filetype = args.filetype,
    winnr = args.winnr,
  }, { __index = Diff })

  log:trace("Using default diff")

  -- Set the diff properties
  vim.cmd("set diffopt=" .. table.concat(config.display.diff.opts, ","))

  local vertical = (config.display.diff.layout == "vertical")

  -- Get current properties
  local buf_opts = {
    ft = self.filetype,
  }
  local win_opts = {
    wrap = vim.wo.wrap,
    lbr = vim.wo.linebreak,
    bri = vim.wo.breakindent,
  }

  --- Minimize the chat buffer window if there's not enough screen estate
  local last_chat = require("codecompanion").last_chat()
  if last_chat and last_chat:is_visible() and config.display.diff.close_chat_at > vim.o.columns then
    last_chat:hide()
  end

  -- Create the diff buffer
  local diff = {
    buf = vim.api.nvim_create_buf(false, true),
    name = "[CodeCompanion] " .. math.random(10000000),
  }
  api.nvim_buf_set_name(diff.buf, diff.name)
  for opt, value in pairs(buf_opts) do
    api.nvim_set_option_value(opt, value, { buf = diff.buf })
  end

  -- Create the diff window
  diff.win = api.nvim_open_win(diff.buf, true, { vertical = vertical, win = self.winnr })
  for opt, value in pairs(win_opts) do
    vim.api.nvim_set_option_value(opt, value, { win = diff.win })
  end
  -- Set the diff buffer to the contents, prior to any modifications
  api.nvim_buf_set_lines(diff.buf, 0, 0, true, self.contents)
  if self.cursor_pos then
    api.nvim_win_set_cursor(diff.win, { self.cursor_pos[1], self.cursor_pos[2] })
  end

  -- Begin diffing
  util.fire("DiffAttached", { diff = "default", bufnr = self.bufnr })
  api.nvim_set_current_win(diff.win)
  vim.cmd("diffthis")
  api.nvim_set_current_win(self.winnr)
  vim.cmd("diffthis")

  log:trace("Using default diff")
  self.diff = diff

  return self
end

---Accept the diff
---@return nil
function Diff:accept()
  return self:teardown()
end

---Reject the diff
---@return nil
function Diff:reject()
  self:teardown()
  return api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.contents)
end

---Close down the diff
---@return nil
function Diff:teardown()
  vim.cmd("diffoff")
  api.nvim_win_close(self.diff.win, false)
  util.fire("DiffDetached", { diff = "default", bufnr = self.bufnr })
end

return Diff
