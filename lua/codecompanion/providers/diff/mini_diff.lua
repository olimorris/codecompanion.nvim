---Utilising the awesome:
---https://github.com/echasnovski/mini.diff

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local ok, diff = pcall(require, "mini.diff")
if not ok then
  return log:error("Failed to load mini.diff: %s", diff)
end

local api = vim.api

local current_source

---@class CodeCompanion.MiniDiff
---@field bufnr number The buffer number of the original buffer
---@field contents string[] The contents of the original buffer
---@field id number A unique identifier for the diff instance
local MiniDiff = {}

---@param args CodeCompanion.DiffArgs
function MiniDiff.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    contents = args.contents,
    id = args.id,
  }, { __index = MiniDiff })

  -- Capture the current source before we disable it
  if vim.b.minidiff_summary then
    current_source = vim.b.minidiff_summary["source_name"]
  end
  diff.disable(self.bufnr)

  -- Change the buffer source
  vim.b[self.bufnr].minidiff_config = {
    source = {
      name = "codecompanion",
      attach = function(bufnr)
        util.fire("DiffAttached", { diff = "mini_diff", bufnr = bufnr, id = self.id })
        diff.set_ref_text(bufnr, self.contents)
        diff.toggle_overlay(self.bufnr)
      end,
      detach = function(bufnr)
        util.fire("DiffDetached", { diff = "mini_diff", bufnr = bufnr, id = self.id })
        self:teardown()
      end,
    },
  }

  diff.enable(self.bufnr)
  log:trace("Using mini.diff")

  return self
end

---Accept the diff
---@return nil
function MiniDiff:accept()
  util.fire("DiffAccepted", { diff = "mini_diff", bufnr = self.bufnr, id = self.id, accept = true })
  vim.b[self.bufnr].minidiff_config = nil
  diff.disable(self.bufnr)
end

---Reject the diff
---@return nil
function MiniDiff:reject()
  util.fire("DiffRejected", { diff = "mini_diff", bufnr = self.bufnr, id = self.id, accept = false })
  api.nvim_buf_set_lines(self.bufnr, 0, -1, true, self.contents)

  vim.b[self.bufnr].minidiff_config = nil
  diff.disable(self.bufnr)
end

---Close down mini.diff
---@return nil
function MiniDiff:teardown()
  -- Revert the source
  if current_source then
    vim.b[self.bufnr].minidiff_config = diff.gen_source[current_source]()
    diff.enable(self.bufnr)
    current_source = nil
  end
end

return MiniDiff
