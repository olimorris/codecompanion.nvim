local log = require("codecompanion.utils.log")

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

return M
