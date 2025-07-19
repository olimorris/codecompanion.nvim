-----------------------
-- Utility Functions
-----------------------
local Utils = {}

-- Create a result object with standard format
function Utils.create_result(status, data)
  return { status = status, data = data }
end

-- Convert URI to filepath
function Utils.uri_to_filepath(uri)
  return uri and uri:gsub("file://", "") or ""
end

-- Convert absolute path to relative path based on cwd
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

-- Check if a file is within project directory
function Utils.is_in_project(filepath)
  local project_root = vim.fn.getcwd()
  return filepath:find(project_root, 1, true) == 1
end

-- Safe buffer validation
function Utils.is_valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

-- Safe filetype retrieval
function Utils.safe_get_filetype(bufnr)
  if not Utils.is_valid_buffer(bufnr) then
    return ""
  end

  local success, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
  return success and filetype or ""
end

-- Safe buffer name retrieval
function Utils.safe_get_buffer_name(bufnr)
  if not Utils.is_valid_buffer(bufnr) then
    return ""
  end

  local success, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  return success and name or ""
end

-- Safe line retrieval
function Utils.safe_get_lines(bufnr, start_row, end_row, strict_indexing)
  if not Utils.is_valid_buffer(bufnr) then
    return {}
  end

  local success, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_row, end_row, strict_indexing or false)
  return success and lines or {}
end

-- Async file operations
function Utils.async_edit_file(filepath, callback)
  vim.schedule(function()
    local success, _ = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(filepath))
    callback(success)
  end)
end

function Utils.async_set_cursor(line, col, callback)
  vim.schedule(function()
    local success = pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
    if success then
      pcall(vim.cmd, "normal! zz")
    end
    callback(success)
  end)
end

-- Check if code block A is enclosed by code block B
function Utils.is_enclosed_by(block_a, block_b)
  if block_a.filename ~= block_b.filename then
    return false
  end
  return block_a.start_line >= block_b.start_line and block_a.end_line <= block_b.end_line
end

return Utils
