---@generic T
---@param t T
---@return T
local function wrap(t)
  return setmetatable({}, { __index = t })
end

local M = wrap(vim)

M.islist = vim.islist or vim.tbl_islist

return M
