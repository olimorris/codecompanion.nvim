local buf_utils = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")

local uv = vim.uv

local M = {}

---Write a full-text replacement to path
---@param path string The file path to write to
---@param content string The full content to write to the file
---@return boolean|nil,string|nil The outcome followed by error message on nil
function M.write_text_file(path, content)
  -- Try to find an existing buffer for the path
  local bufnr = buf_utils.get_bufnr_from_filepath(path)
  if bufnr then
    local ok, err = pcall(function()
      buf_utils.write(bufnr, content)
    end)
    if not ok then
      return nil, ("Buffer write failed for %s: %s"):format(path, tostring(err))
    end
    return true
  end

  -- Otherwise, it's a file
  local ok, err = pcall(function()
    file_utils.write_to_path(path, content)
  end)
  if not ok then
    return nil, ("File write failed for %s: %s"):format(path, tostring(err))
  end
  return true
end

---Read the full text content of a file
---@param path string The file path to read from
---@param opts? table { limit?: number, line?: number }
---@return boolean, any The file content or nil on error (matches pcall-style)
function M.read_text_file(path, opts)
  opts = opts or {}

  -- Quick existence check to return a consistent ENOENT error
  local stat = uv.fs_stat(path)
  if not stat then
    return false, "ENOENT"
  end

  -- Use pcall against file_utils.read to avoid propagation of assert() failures
  local ok, data_or_err = pcall(function()
    return file_utils.read(path)
  end)
  if not ok then
    return false, tostring(data_or_err)
  end

  local content = data_or_err or ""

  -- If a specific line is requested, return only that line (1-indexed)
  if opts.line ~= nil then
    local line_num = tonumber(opts.line) or 0
    if line_num <= 0 then
      return true, ""
    end
    local lines = vim.split(content, "\n", { plain = true })
    return true, lines[line_num] or ""
  end

  -- If a byte/char limit is requested, truncate the returned content
  if opts.limit ~= nil then
    local limit = tonumber(opts.limit) or 0
    if limit > 0 and #content > limit then
      return true, content:sub(1, limit)
    end
  end

  return true, content
end

return M
