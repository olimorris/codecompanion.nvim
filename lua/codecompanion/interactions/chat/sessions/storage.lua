---Read and write session files to disk.
---
---A session is three files sharing a `{created_at}-{slug}` stem:
---  {stem}_meta.json  - title, timestamps and cwd; the only file the picker reads
---  {stem}_chat.json  - messages, settings, context items, adapter and tools
---  {stem}_ui.md      - the rendered chat buffer

local log = require("codecompanion.utils.log")
local serializer = require("codecompanion.interactions.chat.sessions.serializer")

local M = {}

local DEFAULT_DIR = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "codecompanion", "sessions")

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

---@param created_at number Epoch seconds
---@param slug string
---@return string
function M.stem(created_at, slug)
  return os.date("!%Y%m%dT%H%M%S", created_at) .. "-" .. slug
end

---@param stem string
---@param part "meta"|"chat"|"ui"
---@return string
function M.path(stem, part)
  local extension = part == "ui" and ".md" or ".json"
  return vim.fs.joinpath(M.dir(), stem .. "_" .. part .. extension)
end

---@param stem string
---@return boolean
function M.exists(stem)
  return vim.fn.filereadable(M.path(stem, "meta")) == 1
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

---@param path string
---@return table|nil
local function read_json(path)
  local raw = read_file(path)
  if not raw then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    log:error("[sessions::storage] Failed to decode %s: %s", path, decoded)
    return nil
  end
  if decoded.schema_version ~= serializer.SCHEMA_VERSION then
    log:error(
      "[sessions::storage] %s has schema version %s, expected %s",
      path,
      tostring(decoded.schema_version),
      serializer.SCHEMA_VERSION
    )
    return nil
  end
  return decoded
end

---@param path string
---@param record table
---@return boolean ok
local function write_json(path, record)
  local ok, encoded = pcall(vim.json.encode, record)
  if not ok then
    log:error("[sessions::storage] Failed to encode %s: %s", path, encoded)
    return false
  end
  return write_file(path, encoded)
end

---Write a session. Meta is written last so a partial write is never listable.
---@param stem string
---@param record { meta: table, chat: table }
---@param ui_lines? string[]
---@return boolean ok
function M.write(stem, record, ui_lines)
  M.ensure_dir()

  if not write_json(M.path(stem, "chat"), record.chat) then
    return false
  end
  if ui_lines and not write_file(M.path(stem, "ui"), table.concat(ui_lines, "\n")) then
    return false
  end
  return write_json(M.path(stem, "meta"), record.meta)
end

---@param stem string
---@return { meta: table, chat: table, ui_lines: string[]|nil }|nil
function M.read(stem)
  local meta = read_json(M.path(stem, "meta"))
  if not meta then
    return nil
  end
  local chat = read_json(M.path(stem, "chat"))
  if not chat then
    return nil
  end

  local ui_raw = read_file(M.path(stem, "ui"))
  return {
    meta = meta,
    chat = chat,
    ui_lines = ui_raw and vim.split(ui_raw, "\n", { plain = true }) or nil,
  }
end

---@param stem string
---@return boolean ok
function M.delete(stem)
  local ok = pcall(os.remove, M.path(stem, "meta"))
  pcall(os.remove, M.path(stem, "chat"))
  pcall(os.remove, M.path(stem, "ui"))
  return ok
end

---Every session on disk, newest first. Reads only the meta files.
---@return { stem: string, meta: table }[]
function M.list()
  local files = vim.fn.glob(vim.fs.joinpath(M.dir(), "*_meta.json"), true, true)
  table.sort(files, function(a, b)
    return a > b
  end)

  local sessions = {}
  for _, file in ipairs(files) do
    local meta = read_json(file)
    if meta then
      local stem = vim.fn.fnamemodify(file, ":t:r"):gsub("_meta$", "")
      table.insert(sessions, { stem = stem, meta = meta })
    end
  end
  return sessions
end

return M
