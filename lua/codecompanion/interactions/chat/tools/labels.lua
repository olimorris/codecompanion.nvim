local M = {}

M.view = "View"
M.always_accept = "Always accept"
M.accept = "Accept"
M.reject = "Reject"
M.reject_always = "Reject always"
M.cancel = "Cancel"

---Get the resolved keymap keys from shared config
---@return table<string, string>
function M.keymaps()
  local keys = require("codecompanion.config").interactions.shared.keymaps
  return {
    view = keys.view_diff.modes.n,
    always_accept = keys.always_accept.modes.n,
    accept = keys.accept_change.modes.n,
    reject = keys.reject_change.modes.n,
    cancel = keys.cancel.modes.n,
    next_hunk = keys.next_hunk.modes.n,
    previous_hunk = keys.previous_hunk.modes.n,
  }
end

return M
