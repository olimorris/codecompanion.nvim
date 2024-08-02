-- Taken from:
-- https://github.com/stevearc/oil.nvim/blob/master/lua/oil/keymap_util.lua

local plugin_maps = require("codecompanion.keymaps")

local M = {}

---@param rhs string|table|fun()
---@return string|fun(table) rhs
---@return table opts
---@return string|nil mode
local function resolve(rhs)
  if type(rhs) == "string" and vim.startswith(rhs, "keymaps.") then
    return resolve(plugin_maps[vim.split(rhs, ".", { plain = true })[2]])
  elseif type(rhs) == "table" then
    local opts = vim.deepcopy(rhs)
    local callback = opts.callback
    local mode = opts.mode
    if type(rhs.callback) == "string" then
      local action_opts, action_mode
      callback, action_opts, action_mode = resolve(rhs.callback)
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
function M.set(keymaps, bufnr, data)
  for _, map in pairs(keymaps) do
    local callback
    local rhs = resolve(map.callback)

    if type(rhs) == "function" then
      callback = function()
        if data then
          rhs(data)
        else
          rhs()
        end
      end
    else
      callback = rhs
    end

    for mode, key in pairs(map.modes) do
      if mode ~= "" then
        if type(key) == "table" then
          for _, v in ipairs(key) do
            vim.keymap.set(mode, v, callback, { buffer = bufnr })
          end
        else
          vim.keymap.set(mode, key, callback, { buffer = bufnr })
        end
      end
    end
  end
end

return M
