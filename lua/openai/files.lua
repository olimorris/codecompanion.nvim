local M = {}

---@type boolean
M.is_windows = vim.loop.os_uname().version:match("Windows")

---@type boolean
M.is_mac = vim.loop.os_uname().sysname == "Darwin"

---@type string
M.sep = M.is_windows and "\\" or "/"

---@return string
M.join = function(...)
  local joined = table.concat({ ... }, M.sep)
  if M.is_windows then
    joined = joined:gsub("\\\\+", "\\")
  else
    joined = joined:gsub("//+", "/")
  end
  return joined
end

return M
