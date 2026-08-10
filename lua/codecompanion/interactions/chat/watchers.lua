--[[
  Watches attached content for changes, sharing a diff of the changes before
  each chat submission. Buffers are watched via their changedtick and files on
  disk via their modification time.
]]
local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format
local diff = vim.text.diff or vim.diff

---@class CodeCompanion.Chat.Watcher
---@field bufnr? number The buffer being watched (buffer-backed)
---@field changedtick? number The last known changedtick (buffer-backed)
---@field deleted? boolean Whether the buffer has been deleted, pending a message to the LLM
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
    local fence = require("codecompanion.interactions.chat.helpers").code_fence(diff_result)
    return fmt("%sdiff\n%s%s", fence, diff_result, fence)
  end

  return ""
end

---Read a file's content for the LLM
---@param path string
---@return string|nil
local function read_file(path)
  local content = require("codecompanion.interactions.chat.helpers").read_file_for_llm(path)
  if not content or content == "" then
    log:warn("Could not read file: %s", path)
    return nil
  end

  return content
end

---Read a buffer's content for the LLM
---@param bufnr number
---@return string|nil
local function read_buffer(bufnr)
  local path = api.nvim_buf_get_name(bufnr)
  return require("codecompanion.interactions.chat.helpers").read_buffer_for_llm(bufnr, path)
end

---Add a diff of the changes to the message stack
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@param diff_content string
---@return nil
local function add_diff_message(chat, watcher, diff_content)
  local buffer_attr = watcher.bufnr and fmt([[ buffer_number="%s"]], watcher.bufnr) or ""

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = fmt(
      [[<attachment filepath="%s"%s>The file `%s` has been modified. Here are the changes:
%s
</attachment>]],
      watcher.path,
      buffer_attr,
      watcher.path,
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

  local content = read_buffer(args.bufnr)
  if not content then
    return false
  end

  log:debug("Watching buffer %d as `%s`", args.bufnr, args.id)
  self.watchers[args.id] = {
    bufnr = args.bufnr,
    changedtick = api.nvim_buf_get_changedtick(args.bufnr),
    id = args.id,
    last_content = content,
    path = api.nvim_buf_get_name(args.bufnr),
  }

  -- Deletion is recorded rather than acted on, so that the LLM is told about it
  -- on the next turn
  api.nvim_create_autocmd("BufDelete", {
    group = self.augroup,
    buffer = args.bufnr,
    callback = function()
      local watcher = self.watchers[args.id]
      if watcher then
        watcher.deleted = true
      end
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

  local mtime = files.mtime(args.path)
  if not mtime then
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
    mtime = mtime,
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

---Share a diff of the content that has changed since the last turn
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@param content string
---@return nil
local function share_changes(chat, watcher, content)
  local diff_content = format_changes_as_diff(watcher.last_content, content)
  watcher.last_content = content

  if diff_content ~= "" then
    add_diff_message(chat, watcher, diff_content)
  end
end

---Check a watched buffer for changes
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@return boolean removed
function Watchers:_check_buffer(chat, watcher)
  if watcher.deleted or not api.nvim_buf_is_valid(watcher.bufnr) then
    self:unsync(watcher.id)
    add_removed_message(chat, watcher, fmt("The buffer for `%s` has been deleted.", watcher.path))
    return true
  end

  local changedtick = api.nvim_buf_get_changedtick(watcher.bufnr)
  if changedtick == watcher.changedtick then
    return false
  end
  watcher.changedtick = changedtick

  local content = read_buffer(watcher.bufnr)
  if content then
    share_changes(chat, watcher, content)
  end

  return false
end

---Check a watched file for changes
---@param chat CodeCompanion.Chat
---@param watcher CodeCompanion.Chat.Watcher
---@return boolean removed
function Watchers:_check_file(chat, watcher)
  local mtime = files.mtime(watcher.path)
  if not mtime then
    self:unsync(watcher.id)
    add_removed_message(chat, watcher, fmt("The file `%s` has been removed.", watcher.path))
    return true
  end
  if mtime.sec == watcher.mtime.sec and mtime.nsec == watcher.mtime.nsec then
    return false
  end
  watcher.mtime = mtime

  local content = read_file(watcher.path)
  if content then
    share_changes(chat, watcher, content)
  end

  return false
end

---Check all watched context items for changes, adding a diff message for each that has changed
---@param chat CodeCompanion.Chat
---@return nil
function Watchers:check_for_changes(chat)
  local any_removed = false

  for _, item in ipairs(chat.context_items) do
    local watcher = item.opts and item.opts.sync_diff and self.watchers[item.id]
    if watcher then
      local removed
      if watcher.bufnr then
        removed = self:_check_buffer(chat, watcher)
      else
        removed = self:_check_file(chat, watcher)
      end
      if removed then
        item.opts.sync_diff = false
        any_removed = true
      end
    end
  end

  -- Drop the sync icon from context items that are no longer being watched
  if any_removed then
    chat.context:render()
  end
end

return Watchers
