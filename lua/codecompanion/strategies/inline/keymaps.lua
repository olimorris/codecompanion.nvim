local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local M = {}

---Clear a keymap from a specific buffer
---@param keymaps table
---@param bufnr? number
local function clear_map(keymaps, bufnr)
  bufnr = bufnr or 0

  for _, map in pairs(keymaps) do
    for mode, lhs in pairs(map.modes) do
      pcall(vim.keymap.del, mode, lhs, { buffer = bufnr })
    end
  end
end

M.accept_change = {
  desc = "Accept the change from the LLM",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Accepting diff for id=%s", tostring(inline.id))
      inline.diff:accept()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

M.reject_change = {
  desc = "Reject the change from the LLM",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Rejecting diff for id=%d", tostring(inline.id))
      inline.diff:reject()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

M.always_accept = {
  desc = "Accept and enable auto mode",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Auto-accepting diff for id=%s", tostring(inline.id))
      inline.diff:accept()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr)
    end
    vim.g.codecompanion_yolo_mode = true
    log:trace("[Inline] YOLO mode enabled")
  end,
}

M.next_hunk = {
  desc = "Jump to next hunk",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Jumping to next hunk for id=%s", tostring(inline.id))
      inline.diff:jump_to_next_hunk()
    end
  end,
}

M.prev_hunk = {
  desc = "Jump to previous hunk",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Jumping to previous hunk for id=%s", tostring(inline.id))
      inline.diff:jump_to_prev_hunk()
    end
  end,
}

return M
