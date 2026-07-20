-- Part taken from:
-- https://github.com/stevearc/oil.nvim/blob/master/lua/oil/keymap_util.lua

---@class CodeCompanion.Keymaps
---@field bufnr number The buffer number to apply the keymaps to
---@field callbacks table The callbacks to execute for each keymap
---@field data table The CodeCompanion class
---@field keymaps table The keymaps from the user's config
---@field Override CodeCompanion.Keymaps.Override

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
---@param opts? table
---@return nil
function Keymaps:set(opts)
  opts = opts or {}

  for name, map in pairs(self.keymaps) do
    if opts.keymaps and not vim.tbl_contains(opts.keymaps, name) then
      goto continue
    end
    if opts.exclude_keymaps and vim.tbl_contains(opts.exclude_keymaps, name) then
      goto continue
    end
    if map == false then
      goto continue
    end

    local callback
    local rhs, action_opts = self:resolve(map.callback)
    if type(map.condition) == "function" and not map.condition(opts) then
      goto continue
    end

    local default_opts = { desc = map.description or action_opts.desc, buffer = self.bufnr, nowait = true }
    local key_opts = vim.tbl_deep_extend("force", default_opts, map.opts or {})
    if key_opts.chat then
      -- These are reserved for chat specific items and should not be set as keymaps
      key_opts.chat = nil
    end

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
            vim.keymap.set(mode, v, callback, key_opts)
          end
        else
          vim.keymap.set(mode, key, callback, key_opts)
        end
      end
    end
    ::continue::
  end
end

--[[
  Overrides keymaps in a buffer, storing any mappings so they can be restored later
--]]

---@class CodeCompanion.Keymaps.Override
---@field bufnr number The buffer the keymaps are applied to
---@field bound string[] The lhs of each overridden keymap, in the order they were set
---@field overwritten table<string, table|false> The mappings that were replaced, keyed by lhs
local Override = {}

---@param bufnr number
---@return CodeCompanion.Keymaps.Override
function Override.new(bufnr)
  return setmetatable({ bufnr = bufnr, bound = {}, overwritten = {} }, { __index = Override }) ---@type CodeCompanion.Keymaps.Override
end

---Set a normal-mode keymap on the buffer, remembering any mapping it replaces
---@param lhs string
---@param rhs string|function
---@param opts? { desc?: string }
---@return nil
function Override:set(lhs, rhs, opts)
  if self.overwritten[lhs] == nil then
    self.overwritten[lhs] = false
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(self.bufnr, "n")) do
      if map.lhs == lhs then
        self.overwritten[lhs] = map
        break
      end
    end
  end

  opts = vim.tbl_extend("force", { buffer = self.bufnr, nowait = true, silent = true }, opts or {})
  vim.keymap.set("n", lhs, rhs, opts)
  table.insert(self.bound, lhs)
end

---Remove the overridden keymaps and restore any mappings they replaced
---@return nil
function Override:restore()
  for _, lhs in ipairs(self.bound) do
    pcall(vim.keymap.del, "n", lhs, { buffer = self.bufnr })

    local saved = self.overwritten[lhs]
    if saved then
      local rhs = saved.callback
      if not rhs and saved.rhs and saved.rhs ~= "" then
        rhs = saved.rhs
      end
      if rhs then
        pcall(vim.keymap.set, "n", lhs, rhs, {
          buffer = self.bufnr,
          desc = saved.desc,
          expr = saved.expr == 1,
          nowait = saved.nowait == 1,
          silent = saved.silent == 1,
        })
      end
    end
  end
end

Keymaps.Override = Override

return Keymaps
