-- Taken from:
-- https://github.com/stevearc/oil.nvim/blob/master/lua/oil/keymap_util.lua

---@class CodeCompanion.Keymaps
---@field bufnr number The buffer number to apply the keymaps to
---@field callbacks table The callbacks to execute for each keymap
---@field data table The CodeCompanion class
---@field keymaps table The keymaps from the user's config

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

---@class CodeCompanion.Keymaps
local Keymaps = {}

---@param args table
function Keymaps.new(args)
  return setmetatable({
    bufnr = args.bufnr,
    callbacks = args.callbacks,
    data = args.data,
    keymaps = args.keymaps,
  }, { __index = Keymaps })
end

---Resolve the callback for each keymap
---@param rhs string|table|fun()
---@return string|fun(table)|boolean rhs
---@return table opts
---@return string|nil mode
function Keymaps:resolve(rhs)
  if type(rhs) == "string" and vim.startswith(rhs, "keymaps.") then
    return self:resolve(self.callbacks[vim.split(rhs, ".", { plain = true })[2]])
  elseif type(rhs) == "string" then
    return self.callbacks()[rhs], {}
  elseif type(rhs) == "function" then
    return rhs, {}
  elseif type(rhs) == "table" then
    local opts = vim.deepcopy(rhs)
    local callback = opts.callback
    local mode = opts.mode
    if type(rhs.callback) == "string" then
      local action_opts, action_mode
      callback, action_opts, action_mode = self:resolve(rhs.callback)
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

---Set the keymaps
---@return nil
function Keymaps:set()
  for _, map in pairs(self.keymaps) do
    local callback
    local rhs, action_opts = self:resolve(map.callback)
    if type(map.condition) == "function" and not map.condition() then
      goto continue
    end

    local default_opts = { desc = map.description or action_opts.desc, buffer = self.bufnr }
    local opts = vim.tbl_deep_extend("force", default_opts, map.opts or {})

    if type(rhs) == "function" then
      callback = function()
        self.data = self.data or {}
        self.data.position = get_position_info()
        rhs(self.data)
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

return Keymaps
