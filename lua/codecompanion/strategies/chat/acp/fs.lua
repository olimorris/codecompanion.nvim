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
  local lines = vim.split(content, "\n", { plain = true })

  local has_line = opts.line ~= nil
  local has_limit = opts.limit ~= nil

  -- Normalize numeric inputs
  local start = nil
  if has_line then
    start = tonumber(opts.line) or 0
    if start <= 0 then
      start = 1
    end
  else
    start = 1
  end

  if has_limit then
    local limit = tonumber(opts.limit) or 0
    if limit <= 0 then
      return true, ""
    end
    local finish = start + limit - 1
    if start > #lines then
      return true, ""
    end
    if finish >= #lines then
      -- return from start to EOF
      local slice = {}
      for i = start, #lines do
        table.insert(slice, lines[i] or "")
      end
      return true, table.concat(slice, "\n")
    end
    -- return start..finish
    local slice = {}
    for i = start, finish do
      table.insert(slice, lines[i] or "")
    end
    return true, table.concat(slice, "\n")
  end

  -- no limit: if only line was provided, return from that line to EOF
  if has_line then
    if start > #lines then
      return true, ""
    end
    local slice = {}
    for i = start, #lines do
      table.insert(slice, lines[i] or "")
    end
    return true, table.concat(slice, "\n")
  end

  -- neither line nor limit: return full content
  return true, content
end

return M
