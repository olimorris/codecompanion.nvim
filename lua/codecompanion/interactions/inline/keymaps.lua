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

M.stop = {
  callback = function(inline)
    inline:stop()
    clear_map(config.interactions.inline.keymaps, inline.diff.bufnr)
    log:trace("[Inline] Cancelling the request")
  end,
}

return M
