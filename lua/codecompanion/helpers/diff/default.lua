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
---@field bufnr_diff number The buffer number of the diff buffer
---@field winnr_diff number The window number of the diff buffer
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

  -- Get current window properties
  local wrap = vim.wo.wrap
  local linebreak = vim.wo.linebreak
  local breakindent = vim.wo.breakindent
  vim.cmd("set diffopt=" .. table.concat(config.display.diff.opts, ","))

  --- Minimize the chat buffer window if there's not enough screen estate
  local last_chat = require("codecompanion").last_chat()
  if last_chat and last_chat:is_visible() and config.display.diff.close_chat_at > vim.o.columns then
    last_chat:hide()
  end

  -- Create the diff buffer
  if config.display.diff.layout == "vertical" then
    vim.cmd("vsplit")
  else
    vim.cmd("split")
  end

  self.bufnr_diff = api.nvim_create_buf(false, true)
  self.winnr_diff = api.nvim_get_current_win()
  api.nvim_win_set_buf(self.winnr_diff, self.bufnr_diff)
  api.nvim_set_option_value("filetype", self.filetype, { buf = self.bufnr_diff })
  api.nvim_set_option_value("wrap", wrap, { win = self.winnr_diff })
  api.nvim_set_option_value("linebreak", linebreak, { win = self.winnr_diff })
  api.nvim_set_option_value("breakindent", breakindent, { win = self.winnr_diff })

  -- Set the diff buffer to the contents, prior to any modifications
  api.nvim_buf_set_lines(self.bufnr_diff, 0, 0, true, self.contents)
  if self.cursor_pos then
    api.nvim_win_set_cursor(self.winnr_diff, { self.cursor_pos[1], self.cursor_pos[2] })
  end

  -- Begin diffing
  util.fire("DiffAttached", { diff = "default", bufnr = self.bufnr })
  api.nvim_set_current_win(self.winnr_diff)
  vim.cmd("diffthis")
  api.nvim_set_current_win(self.winnr)
  vim.cmd("diffthis")

  log:trace("Using default diff")
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
  api.nvim_win_close(self.winnr_diff, false)
  util.fire("DiffDetached", { diff = "default", bufnr = self.bufnr })
end

return Diff
