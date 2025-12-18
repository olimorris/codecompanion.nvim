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
  local bufnr = buf_utils.get_bufnr_from_path(path)
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
  -- Normalize opts and handle vim.NIL
  if opts == vim.NIL then
    opts = {}
  else
    opts = opts or {}
    if opts.line == vim.NIL then
      opts.line = nil
    end
    if opts.limit == vim.NIL then
      opts.limit = nil
    end
  end

  -- Quick existence check to return a consistent ENOENT error
  local stat = uv.fs_stat(path)
  if not stat then
    return false, "ENOENT"
  end

  -- Read file safely
  local ok, data_or_err = pcall(function()
    return file_utils.read(path)
  end)
  if not ok then
    return false, tostring(data_or_err)
  end

  local content = (data_or_err or ""):gsub("\r\n", "\n"):gsub("\r", "\n")

  -- If no line and no limit requested, return the full raw content immediately.
  if opts.line == nil and opts.limit == nil then
    return true, content
  end

  -- Split once for slicing logic below
  local lines = vim.split(content, "\n", { plain = true })
  local total = #lines

  -- Normalize and coerce inputs
  local start = 1
  if opts.line ~= nil then
    start = tonumber(opts.line) or 0
    if start <= 0 then
      start = 1
    end
  end

  if opts.limit ~= nil then
    local limit = tonumber(opts.limit) or 0
    if limit <= 0 then
      -- per existing behavior: limit <= 0 -> empty string
      return true, ""
    end

    -- If start is beyond EOF, return empty
    if start > total then
      return true, ""
    end

    local finish = start + limit - 1
    if finish > total then
      finish = total
    end

    local slice = {}
    for i = start, finish do
      table.insert(slice, lines[i] or "")
    end
    return true, table.concat(slice, "\n")
  end

  -- only line provided: return from start to EOF (or empty if start > EOF)
  if start > total then
    return true, ""
  end
  local slice = {}
  for i = start, total do
    table.insert(slice, lines[i] or "")
  end

  return true, table.concat(slice, "\n")
end

return M
