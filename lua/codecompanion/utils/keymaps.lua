-- Taken from:
-- https://github.com/stevearc/oil.nvim/blob/master/lua/oil/keymap_util.lua

local plugin_maps = require("codecompanion.keymaps")

local M = {}

---Get the current position of the cursor when the keymap was triggered
---@return table
local function get_position_info()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return {
    line = vim.api.nvim_get_current_line(),
    row = cursor[1],
    col = cursor[2] + 1,
  }
end

---@param rhs string|table|fun()
---@return string|fun(table)|boolean rhs
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
    local rhs, action_opts = resolve(map.callback)
    if type(map.condition) == "function" and not map.condition() then
      goto continue
    end

    local opts = { desc = map.description or action_opts.desc, buffer = bufnr }

    if type(rhs) == "function" then
      callback = function()
        data = data or {}
        data.position = get_position_info()
        rhs(data)
      end
    else
      callback = rhs
    end

    for mode, key in pairs(map.modes) do
      if mode ~= "" then
        if type(key) == "table" then
          for _, v in ipairs(key) do
            vim.keymap.set(mode, v, callback, opts)
          end
        else
          vim.keymap.set(mode, key, callback, opts)
        end
      end
    end
    ::continue::
  end
end

return M
