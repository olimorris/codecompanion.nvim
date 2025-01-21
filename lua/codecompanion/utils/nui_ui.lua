local Split = require("nui.split")

local config = require("codecompanion.config")

local M = {}

---Check if nui is enabled and installed
---@return boolean
function M.enabled()
  local status = pcall(require, "nui.split")
  if not status or not config.display.chat.window.nui then
    return false
  end
  return true
end

---Split window and position it
---@param win_opts table
---@param position string left, right, top, bottom
function M.split(win_opts, position)
  win_opts.position = position
  local win = Split(win_opts)
  win:mount()
end

return M
