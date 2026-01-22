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

---Resolve a diff with common cleanup logic
---@param diff_ui CodeCompanion.DiffUI
---@param opts { event: string, log_action: string, callback?: fun(diff_ui: CodeCompanion.DiffUI) }
---@return boolean success Returns false if already resolved
local function resolve_diff(diff_ui, opts)
  if diff_ui.resolved then
    return false
  end
  diff_ui.resolved = true

  log:trace("[Diff] %s diff for id=%s", opts.log_action, diff_ui.diff_id)
  utils.fire(opts.event, { id = diff_ui.diff_id })

  if opts.callback then
    opts.callback(diff_ui)
  end

  diff_ui:clear()
  diff_ui:close()
  clear_map(config.interactions.inline.keymaps, diff_ui.bufnr)

  return true
end

M.always_accept = {
  desc = "Always accept changes from this chat buffer",
  callback = function(diff_ui, cb)
    resolve_diff(diff_ui, {
      event = "DiffAccepted",
      log_action = "Accepting",
      callback = function(ui)
        if cb then
          return cb(ui)
        end
        local approvals = require("codecompanion.interactions.chat.tools.approvals")
        approvals:always(ui.chat_bufnr, ui.tool_name)
      end,
    })
  end,
}

M.accept_change = {
  desc = "Accept all changes",
  callback = function(diff_ui)
    resolve_diff(diff_ui, { event = "DiffAccepted", log_action = "Accepting" })
  end,
}

M.reject_change = {
  desc = "Reject all changes",
  callback = function(diff_ui)
    resolve_diff(diff_ui, { event = "DiffRejected", log_action = "Rejecting" })
  end,
}

M.close_window = {
  desc = "Close window and reject",
  callback = function(diff_ui)
    resolve_diff(diff_ui, { event = "DiffRejected", log_action = "Closing" })
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
