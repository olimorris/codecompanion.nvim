---Read and write session files to disk.
---
---Layout under the session directory:
---  {slug}_chat.json  — schema-versioned session state
---  {slug}_ui.md      — rendered chat buffer markdown

local log = require("codecompanion.utils.log")

local M = {}

local DEFAULT_DIR = vim.fn.stdpath("data") .. "/codecompanion/sessions"

---Override the storage directory (used by tests).
---@type string|nil
local override_dir = nil

---@return string
function M.dir()
  return override_dir or DEFAULT_DIR
end

---@param path string|nil
function M.set_dir(path)
  override_dir = path
end

---@return nil
function M.ensure_dir()
  vim.fn.mkdir(M.dir(), "p")
end

---@param slug string
---@return string
function M.json_path(slug)
  return M.dir() .. "/" .. slug .. "_chat.json"
end

---@param slug string
---@return string
function M.ui_path(slug)
  return M.dir() .. "/" .. slug .. "_ui.md"
end

---@param slug string
---@return boolean
function M.exists(slug)
  return vim.fn.filereadable(M.json_path(slug)) == 1
end

---@param path string
---@param contents string
---@return boolean ok
local function write_file(path, contents)
  local fd, err = io.open(path, "w")
  if not fd then
    log:error("[sessions::storage] Could not open %s for write: %s", path, err or "unknown")
    return false
  end
  fd:write(contents)
  fd:close()
  return true
end

---@param path string
---@return string|nil
local function read_file(path)
  local fd, err = io.open(path, "r")
  if not fd then
    log:debug("[sessions::storage] Could not read %s: %s", path, err or "unknown")
    return nil
  end
  local contents = fd:read("*a")
  fd:close()
  return contents
end

---@param slug string
---@param data table The encoded JSON-shaped table
---@param ui_lines string[] The rendered chat buffer lines
---@return boolean ok
function M.write(slug, data, ui_lines)
  M.ensure_dir()
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    log:error("[sessions::storage] Failed to encode session %s: %s", slug, encoded)
    return false
  end
  if not write_file(M.json_path(slug), encoded) then
    return false
  end
  if ui_lines and not write_file(M.ui_path(slug), table.concat(ui_lines, "\n")) then
    return false
  end
  return true
end

---@param slug string
---@return table|nil data, string[]|nil ui_lines
function M.read(slug)
  local raw = read_file(M.json_path(slug))
  if not raw then
    return nil, nil
  end
  local ok, data = pcall(vim.json.decode, raw)
  if not ok then
    log:error("[sessions::storage] Failed to decode session %s: %s", slug, data)
    return nil, nil
  end

  local ui_raw = read_file(M.ui_path(slug))
  local ui_lines = ui_raw and vim.split(ui_raw, "\n", { plain = true }) or nil
  return data, ui_lines
end

---@param slug string
---@return boolean ok
function M.delete(slug)
  local ok_json = pcall(os.remove, M.json_path(slug))
  pcall(os.remove, M.ui_path(slug))
  return ok_json
end

---List all session slugs on disk.
---@return string[]
function M.list_slugs()
  local pattern = M.dir() .. "/*_chat.json"
  local files = vim.fn.glob(pattern, true, true)
  local slugs = {}
  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ":t:r") -- strip dir + extension
    local slug = name:gsub("_chat$", "")
    table.insert(slugs, slug)
  end
  return slugs
end

return M
