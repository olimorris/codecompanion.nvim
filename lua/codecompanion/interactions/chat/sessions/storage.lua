--[[
===============================================================================
    File:       codecompanion/interactions/chat/sessions/storage.lua
-------------------------------------------------------------------------------
    Description:
      Reads and writes session files to disk.

      A session is three files which share a `{created_at}-{slug}` stem:

        {stem}_meta.json  Title, timestamps and cwd. The only file the picker reads
        {stem}_chat.json  Messages, settings, context items, adapter and tools
        {stem}_ui.md      The rendered chat buffer

      Meta is written last, so a session whose write died part way through is
      never offered up by the picker.

      `list` is cached and fires `ChatSessionsChanged` whenever that cache is
      dropped, so a picker can hold onto the list rather than re-reading every
      meta file each time it opens.
===============================================================================
--]]

local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local serializer = require("codecompanion.interactions.chat.sessions.serializer")
local utils = require("codecompanion.utils")

local M = {}

local DEFAULT_DIR = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "codecompanion", "sessions")

---Override the storage directory (used by tests)
---@type string|nil
local override_dir = nil

---@type { sessions: { stem: string, meta: table }[], mtime: { sec: number, nsec: number }|nil }|nil
local cache = nil

---Drop the cached session list and tell anything listening that it moved on
---@return nil
function M.invalidate()
  cache = nil
  utils.fire("ChatSessionsChanged")
end

---@return string
function M.dir()
  return override_dir or DEFAULT_DIR
end

---@param path string|nil
function M.set_dir(path)
  override_dir = path
  M.invalidate()
end

---@return nil
function M.ensure_dir()
  files.create_dir_recursive(M.dir())
end

---@param opts { created_at: number, slug: string }
---@return string
function M.stem(opts)
  return os.date("!%Y%m%dT%H%M%S", opts.created_at) .. "-" .. opts.slug
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
  return files.exists(M.path(stem, "meta"))
end

---@param path string
---@param contents string
---@return boolean ok
local function write_file(path, contents)
  local ok, err = pcall(files.write_to_path, path, contents)
  if not ok then
    log:error("[sessions::storage] Could not write %s: %s", path, err)
    return false
  end
  return true
end

---@param path string
---@return string|nil
local function read_file(path)
  if not files.exists(path) then
    return nil
  end

  local ok, contents = pcall(files.read, path)
  if not ok then
    log:debug("[sessions::storage] Could not read %s: %s", path, contents)
    return nil
  end
  return contents
end

---@param path string
---@return table|nil, string|nil reason A sentence the user can be shown
local function read_json(path)
  local raw = read_file(path)
  if not raw then
    return nil, "its files are missing or could not be read"
  end

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    log:debug("[sessions::storage] Failed to decode %s: %s", path, decoded)
    return nil, "one of its files is corrupted"
  end

  if decoded.schema_version ~= serializer.SCHEMA_VERSION then
    log:debug(
      "[sessions::storage] %s has schema version %s, expected %s",
      path,
      tostring(decoded.schema_version),
      serializer.SCHEMA_VERSION
    )
    return nil, "it was saved by a different version of CodeCompanion"
  end

  return decoded, nil
end

---@param path string
---@param contents table
---@return boolean ok
local function write_json(path, contents)
  local ok, encoded = pcall(vim.json.encode, contents)
  if not ok then
    log:error("[sessions::storage] Failed to encode %s: %s", path, encoded)
    return false
  end
  return write_file(path, encoded)
end

---Write a session. Meta is written last so a partial write is never listable
---@param stem string
---@param opts { chat: table, meta: table, ui_lines?: string[] }
---@return boolean ok
function M.write(stem, opts)
  M.ensure_dir()

  if not write_json(M.path(stem, "chat"), opts.chat) then
    return false
  end
  if opts.ui_lines and not write_file(M.path(stem, "ui"), table.concat(opts.ui_lines, "\n")) then
    return false
  end

  local ok = write_json(M.path(stem, "meta"), opts.meta)
  if ok then
    M.invalidate()
  end
  return ok
end

---@param stem string
---@return { meta: table, chat: table, ui_lines: string[]|nil }|nil, string|nil reason
function M.read(stem)
  local meta, reason = read_json(M.path(stem, "meta"))
  if not meta then
    return nil, reason
  end

  local chat
  chat, reason = read_json(M.path(stem, "chat"))
  if not chat then
    return nil, reason
  end

  local ui_raw = read_file(M.path(stem, "ui"))
  return {
    meta = meta,
    chat = chat,
    ui_lines = ui_raw and vim.split(ui_raw, "\n", { plain = true }) or nil,
  },
    nil
end

---@param stem string
---@return nil
function M.delete(stem)
  for _, part in ipairs({ "meta", "chat", "ui" }) do
    local path = M.path(stem, part)
    if files.exists(path) then
      local ok, err = files.delete(path)
      if not ok then
        log:error("[sessions::storage] Could not delete %s: %s", path, err)
      end
    end
  end
  M.invalidate()
end

---Every session on disk, newest first. Reads only the meta files
---@return { stem: string, meta: table }[]
function M.list()
  -- Another Neovim instance can modify sessions
  local mtime = files.mtime(M.dir())
  if cache and vim.deep_equal(cache.mtime, mtime) then
    return cache.sessions
  end

  local meta_files = files.scan_directory(M.dir(), { patterns = "*_meta.json", max_depth = 0 })
  table.sort(meta_files, function(a, b)
    return a > b
  end)

  local sessions = {}
  for _, file in ipairs(meta_files) do
    local meta = read_json(file)
    if meta then
      local stem = vim.fn.fnamemodify(file, ":t:r"):gsub("_meta$", "")
      table.insert(sessions, { stem = stem, meta = meta })
    end
  end

  cache = { sessions = sessions, mtime = mtime }
  return sessions
end

return M
