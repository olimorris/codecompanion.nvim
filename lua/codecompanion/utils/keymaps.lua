-- Taken from:
-- https://github.com/stevearc/oil.nvim/blob/master/lua/oil/keymap_util.lua

local keymaps = require("codecompanion.keymaps")

local M = {}

---@param rhs string|table|fun()
---@return string|fun() rhs
---@return table opts
---@return string|nil mode
M.resolve = function(rhs)
  if type(rhs) == "string" and vim.startswith(rhs, "keymaps.") then
    return M.resolve(keymaps[vim.split(rhs, ".", { plain = true })[2]])
  elseif type(rhs) == "table" then
    local opts = vim.deepcopy(rhs)
    local callback = opts.callback
    local mode = opts.mode
    if type(rhs.callback) == "string" then
      local action_opts, action_mode
      callback, action_opts, action_mode = M.resolve(rhs.callback)
      opts = vim.tbl_extend("keep", opts, action_opts)
      mode = mode or action_mode
    end
    opts.callback = nil
    opts.mode = nil
    return callback, opts, mode
  else
    return rhs, {}
  end
end

---@param keymaps table<string, string|table|fun()>
---@param bufnr integer
---@param data? table
M.set_keymaps = function(keymaps, bufnr, data)
  for k, v in pairs(keymaps) do
    local rhs, opts, mode = M.resolve(v)
    if rhs then
      local callback
      if type(rhs) == "function" then
        callback = function()
          rhs(data or {})
        end
      else
        callback = rhs
      end
      opts = vim.tbl_extend("keep", opts, { buffer = bufnr })
      vim.keymap.set(mode or "", k, callback, opts)
    end
  end
end

return M
