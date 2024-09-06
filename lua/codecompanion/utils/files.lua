local uv = vim.loop

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

---Read the contents of a file
---@param path string
---@return string
M.read = function(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return ""
  end
  local stat = uv.fs_fstat(fd)
  local content = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  return content
end

---Get the filetype of a file
---@param path string
---@return string
M.get_filetype = function(path)
  local ft = vim.filetype.match({ filename = path })
  if not ft then
    ft = ""
  end
  return ft
end

return M
