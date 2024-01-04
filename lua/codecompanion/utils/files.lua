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

---@param path string
M.replace_home = function(path)
  local home = os.getenv("HOME") -- Get the value of the HOME environment variable
  if home then
    home = home:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
    path = path:gsub("^" .. home, "~")
  end
  return path
end

return M
