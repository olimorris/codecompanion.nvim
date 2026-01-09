local log = require("codecompanion.utils.log")
local uv = vim.uv
local fn = vim.fn

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

    local success, err, errname = uv.fs_rmdir(path)
    if not success then
      return false, fmt("Failed to remove directory %s: %s (%s)", path, err, errname)
    end
  else
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

---Base64 encode a given file using the `base64` command.
---@param path string The path to the file to encode
---@return string?, string? The output and error message
function M.base64_encode_file(path)
  local read_ok, content = pcall(M.read, path)
  if read_ok then
    local ok, res = pcall(vim.base64.encode, content)
    if ok then
      return res, nil
    else
      return nil, "Could not base64-encode the file: " .. path
    end
  else
    return nil, string.format("Could not load the file: %s", path)
  end
end

---Get the mimetype from the given file
---@param path string The path to the file
---@return string
function M.get_mimetype(path)
  if fn.executable("file") == 1 then
    local out = vim.system({ "file", "--mime-type", path }):wait()
    if (out.code == 0) and out.stdout then
      local _type, _ = out.stdout:gsub(".*:", "")
      return vim.trim(_type)
    end
  end

  local map = {
    gif = "image/gif",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    png = "image/png",
    webp = "image/webp",
    pdf = "application/pdf",
    rtf = "text/rtf",
    xslx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    csv = "text/csv",
    docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  }

  local extension = vim.fn.fnamemodify(path, ":e")
  extension = extension:lower()

  return map[extension]
end

---Convert a glob pattern to a Lua pattern
---Based on lua-glob-pattern by David Manura
---@param glob string The glob pattern to convert
---@return string lua_pattern The converted Lua pattern
local function globtopattern(glob)
  local p = "^"
  local i = 0
  local c

  local function unescape()
    if c == "\\" then
      i = i + 1
      c = glob:sub(i, i)
      if c == "" then
        p = "[^]"
        return false
      end
    end
    return true
  end

  local function escape(char)
    return char:match("^%w$") and char or "%" .. char
  end

  local function charset_end()
    while true do
      if c == "" then
        p = "[^]"
        return false
      elseif c == "]" then
        p = p .. "]"
        break
      else
        if not unescape() then
          break
        end
        local c1 = c
        i = i + 1
        c = glob:sub(i, i)
        if c == "" then
          p = "[^]"
          return false
        elseif c == "-" then
          i = i + 1
          c = glob:sub(i, i)
          if c == "" then
            p = "[^]"
            return false
          elseif c == "]" then
            p = p .. escape(c1) .. "%-]"
            break
          else
            if not unescape() then
              break
            end
            p = p .. escape(c1) .. "-" .. escape(c)
          end
        elseif c == "]" then
          p = p .. escape(c1) .. "]"
          break
        else
          p = p .. escape(c1)
          i = i - 1
        end
      end
      i = i + 1
      c = glob:sub(i, i)
    end
    return true
  end

  local function charset()
    i = i + 1
    c = glob:sub(i, i)
    if c == "" or c == "]" then
      p = "[^]"
      return false
    elseif c == "^" or c == "!" then
      i = i + 1
      c = glob:sub(i, i)
      if c == "]" then
        -- ignored
      else
        p = p .. "[^"
        if not charset_end() then
          return false
        end
      end
    else
      p = p .. "["
      if not charset_end() then
        return false
      end
    end
    return true
  end

  while true do
    i = i + 1
    c = glob:sub(i, i)
    if c == "" then
      p = p .. "$"
      break
    elseif c == "?" then
      p = p .. "."
    elseif c == "*" then
      p = p .. ".*"
    elseif c == "[" then
      if not charset() then
        break
      end
    elseif c == "\\" then
      i = i + 1
      c = glob:sub(i, i)
      if c == "" then
        p = p .. "\\$"
        break
      end
      p = p .. escape(c)
    else
      p = p .. escape(c)
    end
  end
  return p
end

---Check if a filename matches a single pattern
---Supports glob patterns (*, ?, [abc]) and literal matches
---@param filename string The filename to check (not the full path)
---@param pattern string The pattern to match against
---@return boolean
function M.match_pattern(filename, pattern)
  -- Check for glob pattern characters
  if pattern:match("[%*%?%[]") then
    local lua_pattern = globtopattern(pattern)
    return filename:match(lua_pattern) ~= nil
  else
    -- Allow a literal match
    return filename == pattern
  end
end

---Check if a filename matches any of the provided patterns
---@param filename string The filename to check (not the full path)
---@param patterns string|string[] Pattern or list of patterns to match against
---@return boolean
function M.match_patterns(filename, patterns)
  if type(patterns) == "string" then
    patterns = { patterns }
  end

  for _, pattern in ipairs(patterns) do
    if M.match_pattern(filename, pattern) then
      return true
    end
  end

  return false
end

---Recursively scan a directory and return all file paths
---@param dir_path string The directory path to scan
---@param opts? { patterns?: string|string[] } Optional patterns to filter files
---@return string[] files List of absolute file paths
function M.scan_directory(dir_path, opts)
  opts = opts or {}
  local files = {}

  local function scan_recursively(path)
    local handle = uv.fs_scandir(path)
    if not handle then
      return
    end

    while true do
      local name, type = uv.fs_scandir_next(handle)
      if not name then
        break
      end

      local full_path = vim.fs.joinpath(path, name)

      if type == "directory" then
        scan_recursively(full_path)
      elseif type == "file" then
        if opts.patterns then
          if M.match_patterns(name, opts.patterns) then
            table.insert(files, full_path)
          end
        else
          table.insert(files, full_path)
        end
      end
    end
  end

  scan_recursively(dir_path)
  return files
end

---Normalizes extracted content to Unix format
---@param content string
---@return string
function M.normalize_content(content)
  return (content:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

return M
