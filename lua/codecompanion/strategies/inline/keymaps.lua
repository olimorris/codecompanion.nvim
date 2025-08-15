local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local M = {}

---Clear a keymap from a specific buffer and restore original keymaps
---@param keymaps table
---@param bufnr? integer
---@param original_keymaps? table
local function clear_map(keymaps, bufnr, original_keymaps)
  bufnr = bufnr or 0
  log:debug("[inline::keymaps] Clearing keymaps for buffer %d", bufnr)

  for _, map in pairs(keymaps) do
    for mode, lhs in pairs(map.modes) do
      local keys_to_check = type(lhs) == "table" and lhs or { lhs }

      -- Handle all keys
      for _, key in ipairs(keys_to_check) do
        pcall(vim.keymap.del, mode, key, { buffer = bufnr })
        -- Restore original mapping if it existed
        if original_keymaps then
          local map_key = mode .. ":" .. key
          local original = original_keymaps[map_key]
          if original then
            local restore_opts = {
              buffer = bufnr,
              desc = original.desc,
              nowait = original.nowait == 1,
              silent = original.silent == 1,
              expr = original.expr == 1,
            }
            local rhs = original.rhs or original.callback
            if rhs then
              pcall(vim.keymap.set, mode, key, rhs, restore_opts)
            end
          end
        end
      end
    end
  end
end

M.accept_change = {
  desc = "Accept the change from the LLM",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Accepting diff for id=%s", tostring(inline.id))
      inline.diff:accept()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr, inline.diff._original_keymaps)
    end
  end,
}

M.reject_change = {
  desc = "Reject the change from the LLM",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Rejecting diff for id=%d", tostring(inline.id))
      inline.diff:reject()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr, inline.diff._original_keymaps)
    end
  end,
}

M.always_accept = {
  desc = "Accept and enable auto mode",
  callback = function(inline)
    if inline.diff then
      log:trace("[Inline] Auto-accepting diff for id=%s", tostring(inline.id))
      inline.diff:accept()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr, inline.diff._original_keymaps)
    end
    vim.g.codecompanion_auto_tool_mode = true
    utils.notify("Auto tool mode enabled - future edits will be automatically accepted")
    log:trace("[Inline] Auto tool mode enabled")
  end,
}

return M
