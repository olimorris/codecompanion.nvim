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

---Resolves a path relative to the current working directory.
---@param path string? The path to resolve
---@return string resolved_path The resolved absolute path
M.resolve_path_relative_to_cwd = function(path)
  return vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), path))
end

---Resolves the workspace path relative to the current working directory.
---@return string workspace_file_path The resolved absolute path to the workspace file.
M.get_workspace_file_path = function()
  local config_file_name = require("codecompanion.config").workspace_file
  return M.resolve_path_relative_to_cwd(config_file_name or "codecompanion-workspace.json")
end

return M
