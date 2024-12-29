local config = require("codecompanion.config")

local M = {}

---Clear a keymap from a specific buffer
---@param keymaps table
---@param bufnr? integer
local function clear_map(keymaps, bufnr)
  bufnr = bufnr or 0
  for _, map in pairs(keymaps) do
    for _, key in pairs(map.modes) do
      vim.keymap.del("n", key, { buffer = bufnr })
    end
  end
end

M.accept_change = {
  desc = "Accept the change from the LLM",
  callback = function(inline)
    if inline.diff then
      inline.diff:accept()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

M.reject_change = {
  desc = "Reject the change from the LLM",
  callback = function(inline)
    if inline.diff then
      inline.diff:reject()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

return M
