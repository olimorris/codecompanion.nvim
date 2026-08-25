--[[
  Watchers attach content to a chat buffer that is liable to change. They share
  a diff of changes before the submission of a chat. Buffers are watched by
  their Neovim changedtick and files on disk via their modification time
]]

local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format
local diff = vim.text.diff or vim.diff

---@class CodeCompanion.Chat.Watcher
---@field bufnr? number The buffer being watched
---@field changedtick? number The last known changedtick of the buffer
---@field deleted? boolean Whether the buffer has been deleted, pending a message to the LLM
---@field id string The context item ID the watcher is linked to
---@field last_content string The content last shared with the LLM
---@field mtime? { sec: number, nsec: number } The last known modification time of the file
---@field path? string The file being watched

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
---@param args { chat: CodeCompanion.Chat, diff_content: string, watcher: CodeCompanion.Chat.Watcher}
---@return nil
local function add_diff_message(args)
  local buf_attr = args.watcher.bufnr and fmt([[ buffer_number="%s"]], args.watcher.bufnr) or ""

  args.chat:add_message({
    role = config.constants.USER_ROLE,
    content = fmt(
      [[<attachment filepath="%s"%s>The file `%s` has been modified. Here are the changes:
%s
</attachment>]],
      args.watcher.path,
      buf_attr,
      args.watcher.path,
      args.diff_content
    ),
  }, { context = { id = args.watcher.id }, visible = false })
end

---Add a message that the watched content has been removed
---@param args { chat: CodeCompanion.Chat, watcher: CodeCompanion.Chat.Watcher }
---@return nil
local function add_removed_message(args)
  local content = args.watcher.bufnr and fmt("The buffer for `%s` has been deleted.", args.watcher.path)
    or fmt("The file `%s` has been removed.", args.watcher.path)

  args.chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { context = { id = args.watcher.id }, visible = false })
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

  -- Record a buffer deletion so that we can notify the LLM on the next turn
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
---@param id string
---@return nil
function Watchers:unsync(id)
  if self.watchers[id] then
    log:debug("Stopped watching `%s`", id)
    self.watchers[id] = nil
  end
end

---Share a diff of the content that has changed since the last turn
---@param args { chat: CodeCompanion.Chat, content: string, watcher: CodeCompanion.Chat.Watcher }
---@return nil
local function share_changes(args)
  local diff_content = format_changes_as_diff(args.watcher.last_content, args.content)
  args.watcher.last_content = args.content

  if diff_content ~= "" then
    add_diff_message({ chat = args.chat, watcher = args.watcher, diff_content = diff_content })
  end
end

---Check a watched buffer for changes
---@param args { chat: CodeCompanion.Chat, watcher: CodeCompanion.Chat.Watcher }
---@return boolean removed
function Watchers:_check_buffer(args)
  local chat, watcher = args.chat, args.watcher

  if watcher.deleted or not api.nvim_buf_is_valid(watcher.bufnr) then
    self:unsync(watcher.id)
    add_removed_message({ chat = chat, watcher = watcher })
    return true
  end

  local changedtick = api.nvim_buf_get_changedtick(watcher.bufnr)
  if changedtick == watcher.changedtick then
    return false
  end
  watcher.changedtick = changedtick

  local content = read_buffer(watcher.bufnr)
  if content then
    share_changes({ chat = chat, watcher = watcher, content = content })
  end

  return false
end

---Check a watched file for changes
---@param args { chat: CodeCompanion.Chat, watcher: CodeCompanion.Chat.Watcher }
---@return boolean removed
function Watchers:_check_file(args)
  local chat, watcher = args.chat, args.watcher

  local mtime = files.mtime(watcher.path)
  if not mtime then
    self:unsync(watcher.id)
    add_removed_message({ chat = chat, watcher = watcher })
    return true
  end
  if mtime.sec == watcher.mtime.sec and mtime.nsec == watcher.mtime.nsec then
    return false
  end
  watcher.mtime = mtime

  local content = read_file(watcher.path)
  if content then
    share_changes({ chat = chat, watcher = watcher, content = content })
  end

  return false
end

---Check all watched context items for changes, adding a diff message for each that has changed
---@param chat CodeCompanion.Chat
---@return nil
function Watchers:check_for_changes(chat)
  local had_removals = false

  for _, item in ipairs(chat.context_items) do
    local watcher = item.opts and item.opts.sync_diff and self.watchers[item.id]
    if watcher then
      local removed
      if watcher.bufnr then
        removed = self:_check_buffer({ chat = chat, watcher = watcher })
      else
        removed = self:_check_file({ chat = chat, watcher = watcher })
      end
      if removed then
        item.opts.sync_diff = false
        had_removals = true
      end
    end
  end

  if had_removals then
    -- Drop the sync icon from context items that are no longer being watched
    chat.context:render()
  end
end

return Watchers
