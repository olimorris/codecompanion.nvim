local baseline = require("codecompanion.interactions.code_review.baseline")
local config = require("codecompanion.config")

local api = vim.api

local CONSTANTS = {
  BASELINE_PREFIX = "codecompanion://baseline/",
  WINDOW_OPTIONS = { "breakindent", "linebreak", "wrap" },
}

---@class CodeCompanion.CodeReview.DiffTarget
---@field root string The repo root
---@field path string The changed file, relative to the root
---@field baseline_ref string The ref to diff against, for bring-your-own renderers
---@field line number The hunk's first changed line in the working file
---@field id number The hunk's content hash

-- The two windows the native provider drives. Reused across hunks
local panes = { baseline = nil, active = nil }

local M = {}

---@return table
local function opts()
  return config.interactions.code_review.display.diff
end

---@param win number?
---@return boolean
local function is_open(win)
  return win ~= nil and api.nvim_win_is_valid(win)
end

---Move to the window the review will diff in, opening one if required
---@return nil
local function focus_working_pane()
  if is_open(panes.active) then
    return api.nvim_set_current_win(panes.active)
  end

  -- Step out of the quickfix window
  local review_win = api.nvim_get_current_win()
  vim.cmd("wincmd p")
  if api.nvim_get_current_win() == review_win then
    vim.cmd("aboveleft split")
  end
  panes.active = api.nvim_get_current_win()
end

---@param lines string[]
---@param path string
---@return nil
local function render_baseline(lines, path)
  local filetype = vim.bo.filetype
  local window_options = {}
  for _, name in ipairs(CONSTANTS.WINDOW_OPTIONS) do
    window_options[name] = vim.wo[panes.active][name]
  end

  if is_open(panes.baseline) then
    api.nvim_set_current_win(panes.baseline)
  else
    vim.cmd(opts().layout == "horizontal" and "aboveleft split" or "leftabove vsplit")
    panes.baseline = api.nvim_get_current_win()
  end

  local scratch = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(panes.baseline, scratch)
  api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  pcall(api.nvim_buf_set_name, scratch, CONSTANTS.BASELINE_PREFIX .. path)
  vim.bo[scratch].filetype = filetype
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].swapfile = false
  vim.bo[scratch].modifiable = false
  for name, value in pairs(window_options) do
    vim.wo[panes.baseline][name] = value
  end
  vim.cmd("diffthis")
end

---Show the hunk in Neovim's native diff
---@param target CodeCompanion.CodeReview.DiffTarget
---@return nil
function M.native(target)
  local before = baseline.show(target.root, target.path)

  focus_working_pane()
  vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(target.root, target.path)))
  vim.cmd("diffthis")

  render_baseline(before, target.path)

  api.nvim_set_current_win(panes.active)
  pcall(api.nvim_win_set_cursor, panes.active, { target.line, 0 })
  vim.cmd("normal! zv")
end

---Render a hunk with the diff provider
---@param target CodeCompanion.CodeReview.DiffTarget
---@return nil
function M.show(target)
  if not opts().enabled then
    return
  end
  if type(opts().provider) == "function" then
    return opts().provider(target)
  end

  return M.native(target)
end

return M
