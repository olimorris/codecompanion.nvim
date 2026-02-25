local Path = require("plenary.path")

local api = vim.api
local fmt = string.format

local M = {}

---Write file content to disk
---@param path string
---@param content string
---@param info table|nil
---@return boolean, string|nil
function M.write_file(path, content, info)
  info = info or {}

  -- Check for concurrent modifications
  if info.mtime then
    local stat = vim.uv.fs_stat(path)
    if stat and stat.mtime.sec ~= info.mtime then
      return false, fmt("File modified by another process (expected mtime: %d, actual: %d)", info.mtime, stat.mtime.sec)
    end
  end

  -- Preserve trailing newline behavior
  if info.has_trailing_newline == false and content:match("\n$") then
    content = content:gsub("\n$", "")
  elseif info.has_trailing_newline == true and not content:match("\n$") then
    content = content .. "\n"
  end

  local p = Path:new(path)
  local ok, err = pcall(function()
    p:write(content, "w")
  end)

  if not ok then
    return false, fmt("Failed to write file: `%s`", err)
  end

  -- Reload buffer if loaded
  local bufnr = vim.fn.bufnr(p.filename)
  if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
    api.nvim_command("checktime " .. bufnr)
  end

  return true, nil
end

---Read file content from disk
---@param path string
---@return string|nil, string|nil, table|nil The content, error, and file info
function M.read_file(path)
  local p = Path:new(path)
  if not p:exists() or not p:is_file() then
    return nil, fmt("File does not exist or is not a file: `%s`", path)
  end

  local content = p:read()
  if not content then
    return nil, fmt("Could not read file content: `%s`", path)
  end

  local stat = vim.uv.fs_stat(path)
  local info = {
    has_trailing_newline = content:match("\n$") ~= nil,
    is_empty = content == "",
    mtime = stat and stat.mtime.sec or nil,
  }

  return content, nil, info
end

return M
