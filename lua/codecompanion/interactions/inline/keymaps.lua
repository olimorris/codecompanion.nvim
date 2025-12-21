local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

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
      clear_map(config.interactions.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

M.reject_change = {
  desc = "Reject the change from the LLM",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Rejecting diff for id=%d", tostring(inline.id))
      inline.diff:reject()
      clear_map(config.interactions.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

M.always_accept = {
  desc = "Accept and enable auto mode",
  callback = function(inline)
    local approvals = require("codecompanion.interactions.chat.tools.approvals")
    approvals:toggle_yolo_mode(inline.bufnr)

    if inline.diff then
      log:trace("[Inline] Auto-accepting diff for id=%s", tostring(inline.id))
      inline.diff:accept()
      clear_map(config.interactions.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

M.stop = {
  callback = function(inline)
    inline:stop()
    clear_map(config.interactions.inline.keymaps, inline.diff.bufnr)
    log:trace("[Inline] Cancelling the request")
  end,
}

return M
