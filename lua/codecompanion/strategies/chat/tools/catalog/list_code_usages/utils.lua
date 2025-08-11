local api = vim.api

---@class ListCodeUsages.Utils
local Utils = {}

---@param status "success"|"error" The status of the operation
---@param data any The result data or error message
---@return table Result object with status and data fields
function Utils.create_result(status, data)
  return { status = status, data = data }
end

---@param uri string|nil The file URI to convert
---@return string The local filesystem path, or empty string if uri is nil
function Utils.uri_to_filepath(uri)
  return uri and uri:gsub("file://", "") or ""
end

---@param filepath string|nil The absolute filepath to convert
---@return string The relative path, filename only, or empty string if filepath is nil
function Utils.make_relative_path(filepath)
  if not filepath or filepath == "" then
    return ""
  end

  local cwd = vim.fn.getcwd()

  -- Normalize paths to handle different separators
  local normalized_cwd = cwd:gsub("\\", "/")
  local normalized_filepath = filepath:gsub("\\", "/")

  -- Ensure cwd ends with separator for proper matching
  if not normalized_cwd:match("/$") then
    normalized_cwd = normalized_cwd .. "/"
  end

  -- Check if filepath starts with cwd
  if normalized_filepath:find(normalized_cwd, 1, true) == 1 then
    -- Return relative path
    return normalized_filepath:sub(#normalized_cwd + 1)
  else
    -- If not within cwd, return just the filename
    return normalized_filepath:match("([^/]+)$") or normalized_filepath
  end
end

---@param filepath string The absolute filepath to check
---@return boolean True if the file is within the project directory
function Utils.is_in_project(filepath)
  local project_root = vim.fn.getcwd()
  return filepath:find(project_root, 1, true) == 1
end

---@param bufnr number|nil The buffer number to validate
---@return boolean True if the buffer is valid and exists
function Utils.is_valid_buffer(bufnr)
  return bufnr and api.nvim_buf_is_valid(bufnr)
end

---@param bufnr number The buffer number to get filetype from
---@return string The filetype string, or empty string if not available
function Utils.safe_get_filetype(bufnr)
  if not Utils.is_valid_buffer(bufnr) then
    return ""
  end

  local success, filetype = pcall(api.nvim_get_option_value, "filetype", { buf = bufnr })
  return success and filetype or ""
end

---@param bufnr number The buffer number to get name from
---@return string The buffer name/filepath, or empty string if not available
function Utils.safe_get_buffer_name(bufnr)
  if not Utils.is_valid_buffer(bufnr) then
    return ""
  end

  local success, name = pcall(api.nvim_buf_get_name, bufnr)
  return success and name or ""
end

---@param bufnr number The buffer number to get lines from
---@param start_row number The starting row (0-indexed)
---@param end_row number The ending row (0-indexed, exclusive)
---@param strict_indexing boolean|nil Whether to use strict indexing (optional)
---@return string[] Array of lines, or empty array if not available
function Utils.safe_get_lines(bufnr, start_row, end_row, strict_indexing)
  if not Utils.is_valid_buffer(bufnr) then
    return {}
  end

  local success, lines = pcall(api.nvim_buf_get_lines, bufnr, start_row, end_row, strict_indexing or false)
  return success and lines or {}
end

---@param filepath string The path to the file to open
---@param callback function Callback function called with success boolean
function Utils.async_edit_file(filepath, callback)
  vim.schedule(function()
    local success, _ = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(filepath))
    callback(success)
  end)
end

---@param line number The line number to position cursor at (1-indexed)
---@param col number The column number to position cursor at (0-indexed)
---@param callback function Callback function called with success boolean
function Utils.async_set_cursor(line, col, callback)
  vim.schedule(function()
    local success = pcall(api.nvim_win_set_cursor, 0, { line, col })
    if success then
      pcall(vim.cmd, "normal! zz")
    end
    callback(success)
  end)
end

---@param block_a table Code block with filename, start_line, end_line fields
---@param block_b table Code block with filename, start_line, end_line fields
---@return boolean True if block_a is completely enclosed by block_b
function Utils.is_enclosed_by(block_a, block_b)
  if block_a.filename ~= block_b.filename then
    return false
  end
  return block_a.start_line >= block_b.start_line and block_a.end_line <= block_b.end_line
end

return Utils
