local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api

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

M.always_accept = {
  desc = "Always accept changes from this chat buffer",
  callback = function(diff_ui)
    -- There might be an edge case where a user has made a decision on the diff
    -- and the window has then closed, causing `WinClosed` to fire. So we put
    -- a guard here to check for this and repeat across all the keymaps.
    if diff_ui.resolved then
      return
    end
    diff_ui.resolved = true

    log:trace("[Diff] Accepting diff for id=%s", diff_ui.diff_id)
    utils.fire("DiffAccepted", { id = diff_ui.diff_id })

    local approvals = require("codecompanion.interactions.chat.tools.approvals")
    approvals:always(diff_ui.chat_bufnr, diff_ui.tool_name)

    diff_ui:clear()
    diff_ui:close()
    clear_map(config.interactions.inline.keymaps, diff_ui.bufnr)
  end,
}

M.accept_change = {
  desc = "Accept all changes",
  callback = function(diff_ui)
    if diff_ui.resolved then
      return
    end
    diff_ui.resolved = true

    log:trace("[Diff] Accepting diff for id=%s", diff_ui.diff_id)
    utils.fire("DiffAccepted", { id = diff_ui.diff_id })

    diff_ui:clear()
    diff_ui:close()
    clear_map(config.interactions.inline.keymaps, diff_ui.bufnr)
  end,
}

M.reject_change = {
  desc = "Reject all changes",
  callback = function(diff_ui)
    if diff_ui.resolved then
      return
    end
    diff_ui.resolved = true

    log:trace("[Diff] Rejecting diff for id=%s", diff_ui.diff_id)
    utils.fire("DiffRejected", { id = diff_ui.diff_id })

    diff_ui:clear()
    diff_ui:close()
    clear_map(config.interactions.inline.keymaps, diff_ui.bufnr)
  end,
}

M.close_window = {
  desc = "Close window and reject",
  callback = function(diff_ui)
    if diff_ui.resolved then
      return
    end
    diff_ui.resolved = true

    log:trace("[Diff] Closing diff window for id=%s", diff_ui.diff_id)
    utils.fire("DiffRejected", { id = diff_ui.diff_id })

    diff_ui:clear()
    diff_ui:close()
    clear_map(config.interactions.inline.keymaps, diff_ui.bufnr)
  end,
}

M.next_hunk = {
  desc = "Next hunk",
  callback = function(diff_ui)
    local cursor = api.nvim_win_get_cursor(diff_ui.winnr)
    diff_ui:next_hunk(cursor[1])
  end,
}

M.previous_hunk = {
  desc = "Previous hunk",
  callback = function(diff_ui)
    local cursor = api.nvim_win_get_cursor(diff_ui.winnr)
    diff_ui:previous_hunk(cursor[1])
  end,
}

return M
