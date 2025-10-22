-- Taken from the awesome:
-- https://github.com/S1M0N38/dante.nvim

---@class CodeCompanion.Diff
---@field bufnr number The buffer number of the original buffer
---@field contents string[] The contents of the original buffer
---@field cursor_pos number[] The position of the cursor in the original buffer
---@field filetype string The filetype of the original buffer
---@field id number A unique identifier for the diff instance
---@field winnr number The window number of the original buffer
---@field diff table The table containing the diff buffer and window

---@class CodeCompanion.DiffArgs
---@field bufnr number
---@field contents string[]
---@field cursor_pos? number[]
---@field filetype string
---@field id number A unique identifier for the diff instance-
---@field winnr number

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api

---@class CodeCompanion.Diff
local Diff = {}

---@param args CodeCompanion.DiffArgs
function Diff.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    contents = args.contents,
    cursor_pos = args.cursor_pos or nil,
    filetype = args.filetype,
    id = args.id,
    winnr = args.winnr,
  }, { __index = Diff })

  log:trace("Using default diff")

  local split_opts = config.display.diff.provider_opts.split

  -- Set the diff properties
  vim.cmd("set diffopt=" .. table.concat(split_opts.opts, ","))

  local vertical = (split_opts.layout == "vertical")

  -- Get current properties
  local buf_opts = {
    ft = utils.safe_filetype(self.filetype),
  }
  local win_opts = {
    wrap = vim.wo.wrap,
    lbr = vim.wo.linebreak,
    bri = vim.wo.breakindent,
  }

  --- Minimize the chat buffer window if there's not enough screen estate
  local last_chat = require("codecompanion").last_chat()
  if last_chat and last_chat.ui:is_visible() and split_opts.close_chat_at > vim.o.columns then
    last_chat.ui:hide()
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
  api.nvim_buf_set_lines(diff.buf, 0, -1, true, self.contents)
  if self.cursor_pos then
    api.nvim_win_set_cursor(diff.win, { self.cursor_pos[1], self.cursor_pos[2] })
  end

  -- Begin diffing
  utils.fire("DiffAttached", { diff = "default", bufnr = self.bufnr, id = self.id, winnr = self.winnr })
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
  utils.fire("DiffAccepted", { diff = "default", bufnr = self.bufnr, id = self.id, accept = true })
  return self:teardown()
end

---Reject the diff
---@return nil
function Diff:reject()
  utils.fire("DiffRejected", { diff = "default", bufnr = self.bufnr, id = self.id, accept = false })
  self:teardown()
  return api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.contents)
end

---Close down the diff
---@return nil
function Diff:teardown()
  vim.cmd("diffoff")
  api.nvim_buf_delete(self.diff.buf, {})
  utils.fire("DiffDetached", { diff = "default", bufnr = self.bufnr, id = self.id, winnr = self.diff.win })
end

return Diff
