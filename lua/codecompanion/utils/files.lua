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

---Check if a file or directory exists at the given path
---@param path string The file or directory path to check
---@return boolean
function M.exists(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil
end

---Delete a file or directory recursively
---@param path string The file or directory path to delete
---@return boolean success, string? error_message
function M.delete(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return false, fmt("Path does not exist: %s", path)
  end

  if stat.type == "directory" then
    -- Read directory contents
    local handle = uv.fs_scandir(path)
    if handle then
      while true do
        local name, _ = uv.fs_scandir_next(handle)
        if not name then
          break
        end
        local child_path = path .. "/" .. name
        local success, err = M.delete(child_path)
        if not success then
          return false, err
        end
      end
    end
    -- Remove the empty directory
    local success, err, errname = uv.fs_rmdir(path)
    if not success then
      return false, fmt("Failed to remove directory %s: %s (%s)", path, err, errname)
    end
  else
    -- Remove file
    local success, err, errname = uv.fs_unlink(path)
    if not success then
      return false, fmt("Failed to remove file %s: %s (%s)", path, err, errname)
    end
  end

  return true, nil
end

---Rename or move a file or directory
---@param old_path string The current path
---@param new_path string The new path
---@return boolean success, string? error_message
function M.rename(old_path, new_path)
  if not M.exists(old_path) then
    return false, fmt("Source path does not exist: %s", old_path)
  end

  -- Create parent directory if needed
  local parent_dir = vim.fn.fnamemodify(new_path, ":h")
  if parent_dir ~= "" and not M.exists(parent_dir) then
    local success, err = M.create_dir_recursive(parent_dir)
    if not success then
      return false, err
    end
  end

  local success, err, errname = uv.fs_rename(old_path, new_path)
  if not success then
    return false, fmt("Failed to rename %s to %s: %s (%s)", old_path, new_path, err, errname)
  end

  return true, nil
end

---Read file content as lines
---@param path string The file path
---@return string[]|nil lines, string? error_message
function M.read_lines(path)
  if not M.exists(path) then
    return nil, fmt("File does not exist: %s", path)
  end

  local content = M.read(path)
  return vim.split(content, "\n", { plain = true })
end

---List directory contents
---@param path string The directory path
---@return string[]|nil entries, string? error_message
function M.list_dir(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return nil, fmt("Path does not exist: %s", path)
  end

  if stat.type ~= "directory" then
    return nil, fmt("Path is not a directory: %s", path)
  end

  local entries = {}
  local handle = uv.fs_scandir(path)
  if not handle then
    return nil, fmt("Failed to open directory: %s", path)
  end

  while true do
    local name, _ = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    table.insert(entries, name)
  end

  return entries
end

---Check if path is a directory
---@param path string The path to check
---@return boolean
function M.is_dir(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" or false
end

---Read the content of a file at a given path
---@param path string The file to read
---@return string
function M.read(path)
  local fd = assert(uv.fs_open(path, "r", 420))
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0)) or ""
  assert(uv.fs_close(fd))

  return data
end

return M
