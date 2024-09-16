-- Taken from the awesome:
-- https://github.com/echasnovski/mini.diff

local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

local ok, mini_diff = pcall(require, "mini.diff")
if not ok then
  return log:error("Failed to load mini.diff: %s", mini_diff)
end

local api = vim.api

---@class CodeCompanion.MiniDiff
---@field bufnr number The buffer number of the original buffer
---@field cursor_pos number[] The position of the cursor in the original buffer
---@field filetype string The filetype of the original buffer
---@field contents string[] The contents of the original buffer
---@field winnr number The window number of the original buffer
---@field bufnr_diff number The buffer number of the diff buffer
---@field winnr_diff number The window number of the diff buffer
local MiniDiff = {}

---@param args CodeCompanion.DiffArgs
---@return CodeCompanion.MiniDiff
function MiniDiff.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    contents = args.contents,
    cursor_pos = args.cursor_pos or nil,
    filetype = args.filetype,
    winnr = args.winnr,
  }, { __index = MiniDiff })

  mini_diff.enable(self.bufnr)
  mini_diff.toggle_overlay(self.bufnr)

  log:trace("Using mini.diff")

  return self
end

---Accept the diff
---@return nil
function MiniDiff:accept()
  return self:teardown()
end

---Reject the diff
---@return nil
function MiniDiff:reject()
  self:teardown()
  return api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.contents)
end

---Close down mini.diff
---@return nil
function MiniDiff:teardown()
  return mini_diff.disable(self.bufnr)
end

return MiniDiff
