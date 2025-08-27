local log = require("codecompanion.utils.log")
local uv = vim.uv

local fmt = string.format

local M = {}

---Recursively create directories
---@param path string The directory path to create
---@return boolean success, string? error_message
function M.create_dir_recursive(path)
  -- Normalize path and check if we've reached root directory
  local normalized = vim.fs.normalize(path)
  if normalized == "/" or normalized:match("^[A-Z]:[\\/]?$") then
    return true -- Already at root directory
  end

  local parent = vim.fs.dirname(normalized)
  if parent ~= normalized and not vim.uv.fs_stat(parent) then
    local success, err = M.create_dir_recursive(parent)
    if not success then
      return false, err
    end
  end

  local success, err, errname = vim.uv.fs_mkdir(normalized, 493)
  if not success and errname ~= "EEXIST" then
    local error_msg = fmt("Failed to create directory %s: %s (%s)", normalized, err, errname)
    log:error("create_dir_recursive: %s", error_msg)
    return false, error_msg
  end

  return true, nil
end

---Write content to a file, creating directories as needed
---@param path string The file path to write to
---@param content string The content to write to the file
---@return boolean
function M.write_to_path(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  local fd = assert(uv.fs_open(path, "w", 420)) -- 0644
  assert(uv.fs_write(fd, content or "", 0))
  assert(uv.fs_close(fd))

  return true
end

---Read the content of a file at a given path
---@param path string The file path to write to
---@return string
function M.read(path)
  local fd = assert(uv.fs_open(path, "r", 420))
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0)) or ""
  assert(uv.fs_close(fd))

  return data
end

return M
