--[[
  Watches attached content for changes, sharing a diff of the changes before
  each chat submission. Buffers are watched via their changedtick and files on
  disk via their modification time.
]]
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format
local diff = vim.text.diff or vim.diff

---@class CodeCompanion.Chat.Watcher
---@field bufnr? number The buffer being watched (buffer-backed)
---@field changedtick? number The last known changedtick (buffer-backed)
---@field id string The context item ID the watcher is linked to
---@field last_content string The content last shared with the LLM
---@field mtime? { sec: number, nsec: number } The last known modification time (file-backed)
---@field path? string The file being watched (file-backed)

---@class CodeCompanion.Chat.Watchers
---@field augroup number The autocmd group ID
---@field watchers table<string, CodeCompanion.Chat.Watcher> Watchers keyed by context item ID
local Watchers = {}

local instance_count = 0

---@return CodeCompanion.Chat.Watchers
function Watchers.new()
  instance_count = instance_count + 1
  return setmetatable({
    augroup = api.nvim_create_augroup(fmt("codecompanion.watchers.%d", instance_count), { clear = true }),
    watchers = {},
  }, { __index = Watchers })
end

---Generate a unified diff between the content last shared and the current content
---@param old_content string
---@param new_content string
---@return string
local function format_changes_as_diff(old_content, new_content)
  local diff_result = diff(old_content .. "\n", new_content .. "\n", {
    result_type = "unified",
    ctxlen = 3,
    algorithm = "myers",
  })

  if diff_result and diff_result ~= "" then
    return fmt("````diff\n%s````", diff_result)
  end

  return ""
end

---Read a file's content for the LLM
---@param path string
---@return string|nil
local function read_file(path)
  local content = require("codecompanion.interactions.chat.helpers").file_content_for_llm(path)
  if not content or content == "" then
    log:warn("Could not read file: %s", path)
    return nil
  end
  return content
end

---Add a diff of the changes to the message stack
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@param diff_content string
---@return nil
local function add_diff_message(chat, watcher, diff_content)
  local path = watcher.path or api.nvim_buf_get_name(watcher.bufnr)
  local buffer_attr = watcher.bufnr and fmt([[ buffer_number="%s"]], watcher.bufnr) or ""

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = fmt(
      [[<attachment filepath="%s"%s>The file `%s` has been modified. Here are the changes:
%s
</attachment>]],
      path,
      buffer_attr,
      path,
      diff_content
    ),
  }, { context = { id = watcher.id }, visible = false })
end

---Add a message that the watched content has been removed
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@param content string
---@return nil
local function add_removed_message(chat, watcher, content)
  chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { context = { id = watcher.id }, visible = false })
end

---Watch a buffer for changes
---@param args { bufnr: number, id: string }
---@return boolean synced
function Watchers:sync_buffer(args)
  if self.watchers[args.id] then
    return true
  end
  if not api.nvim_buf_is_valid(args.bufnr) then
    log:debug("Cannot watch invalid buffer: %d", args.bufnr)
    return false
  end

  log:debug("Watching buffer %d as `%s`", args.bufnr, args.id)
  self.watchers[args.id] = {
    bufnr = args.bufnr,
    changedtick = api.nvim_buf_get_changedtick(args.bufnr),
    id = args.id,
    last_content = table.concat(api.nvim_buf_get_lines(args.bufnr, 0, -1, false), "\n"),
  }

  api.nvim_create_autocmd("BufDelete", {
    group = self.augroup,
    buffer = args.bufnr,
    callback = function()
      self:unsync(args.id)
    end,
  })

  return true
end

---Watch a file on disk for changes
---@param args { id: string, path: string }
---@return boolean synced
function Watchers:sync_file(args)
  if self.watchers[args.id] then
    return true
  end

  local stat = vim.uv.fs_stat(args.path)
  if not stat then
    log:debug("Cannot watch file, not found: %s", args.path)
    return false
  end

  local content = read_file(args.path)
  if not content then
    return false
  end

  log:debug("Watching file `%s` as `%s`", args.path, args.id)
  self.watchers[args.id] = {
    id = args.id,
    last_content = content,
    mtime = { sec = stat.mtime.sec, nsec = stat.mtime.nsec },
    path = args.path,
  }

  return true
end

---Stop watching a context item
---@param id string The context item ID
---@return nil
function Watchers:unsync(id)
  if self.watchers[id] then
    log:debug("Stopped watching `%s`", id)
    self.watchers[id] = nil
  end
end

---Check a watched buffer for changes
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@return nil
function Watchers:_check_buffer(chat, watcher)
  if not api.nvim_buf_is_valid(watcher.bufnr) then
    self:unsync(watcher.id)
    return add_removed_message(chat, watcher, fmt("Buffer %d has been removed.", watcher.bufnr))
  end

  local changedtick = api.nvim_buf_get_changedtick(watcher.bufnr)
  if changedtick == watcher.changedtick then
    return
  end
  watcher.changedtick = changedtick

  local content = table.concat(api.nvim_buf_get_lines(watcher.bufnr, 0, -1, false), "\n")
  local diff_content = format_changes_as_diff(watcher.last_content, content)
  watcher.last_content = content

  if diff_content ~= "" then
    add_diff_message(chat, watcher, diff_content)
  end
end

---Check a watched file for changes
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@return nil
function Watchers:_check_file(chat, watcher)
  local stat = vim.uv.fs_stat(watcher.path)
  if not stat then
    self:unsync(watcher.id)
    return add_removed_message(chat, watcher, fmt("The file `%s` has been removed.", watcher.path))
  end
  if stat.mtime.sec == watcher.mtime.sec and stat.mtime.nsec == watcher.mtime.nsec then
    return
  end
  watcher.mtime = { sec = stat.mtime.sec, nsec = stat.mtime.nsec }

  local content = read_file(watcher.path)
  if not content then
    return
  end

  local diff_content = format_changes_as_diff(watcher.last_content, content)
  watcher.last_content = content

  if diff_content ~= "" then
    add_diff_message(chat, watcher, diff_content)
  end
end

---Check all watched context items for changes, adding a diff message for each that has changed
---@param chat CodeCompanion.Chat
---@return nil
function Watchers:check_for_changes(chat)
  for _, item in ipairs(chat.context_items) do
    if item.opts and item.opts.sync_diff then
      local watcher = self.watchers[item.id]
      if watcher then
        if watcher.bufnr then
          self:_check_buffer(chat, watcher)
        else
          self:_check_file(chat, watcher)
        end
      end
    end
  end
end

return Watchers
