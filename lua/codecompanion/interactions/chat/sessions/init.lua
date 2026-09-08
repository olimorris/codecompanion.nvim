--[[
===============================================================================
    File:       codecompanion/interactions/chat/sessions/init.lua
-------------------------------------------------------------------------------
    Description:
      Saves chat buffers to disk and restores them into new ones.

===============================================================================
--]]

local config = require("codecompanion.config")
local context = require("codecompanion.interactions.chat.context")
local log = require("codecompanion.utils.log")
local serializer = require("codecompanion.interactions.chat.sessions.serializer")
local slug = require("codecompanion.interactions.chat.sessions.utils.slug")
local storage = require("codecompanion.interactions.chat.sessions.storage")
local utils = require("codecompanion.utils")

local api = vim.api

local M = {}

local MAX_TITLE_LENGTH = 50

---@type table<number, { slug: string, created_at: number, title: string }>
local sessions = {}

---@return boolean
local function autosave_enabled()
  return config.interactions.chat.sessions.autosave
end

---@return boolean
local function continuous_save_enabled()
  return config.interactions.chat.sessions.continuous_save
end

---@param chat CodeCompanion.Chat
---@param opts { title: string, created_at: number }
---@return string slug
local function resolve_slug(chat, opts)
  local entry = sessions[chat.id]
  return slug.disambiguate(slug.slugify(opts.title), {
    is_taken = function(candidate)
      return storage.exists(storage.stem({ created_at = opts.created_at, slug = candidate }))
    end,
    own_slug = entry and entry.slug,
  })
end

---Locate rendered context blocks via the markdown parser
---@param lines string[]
---@return { first: number, last: number }[]|nil
local function find_context_blocks(lines)
  local source = table.concat(lines, "\n")

  local ok, parser = pcall(vim.treesitter.get_string_parser, source, "markdown")
  if not ok or not parser then
    return nil
  end

  local tree
  ok, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not ok or not tree then
    return nil
  end

  local query
  ok, query = pcall(vim.treesitter.query.parse, "markdown", "(block_quote) @block")
  if not ok or not query then
    return nil
  end

  local blocks = {}
  for _, node in query:iter_captures(tree:root(), source) do
    local start_row, _, end_row, end_column = node:range()
    if lines[start_row + 1] == context.HEADER then
      local last = end_column == 0 and end_row or end_row + 1
      if lines[last + 1] == "" then
        last = last + 1
      end
      table.insert(blocks, { first = start_row + 1, last = last })
    end
  end

  return blocks
end

---Keep only the most recent context block, reducing duplication in the buffer
---@param lines string[]
---@return string[]
local function prune_context_blocks(lines)
  local blocks = find_context_blocks(lines)
  if not blocks or #blocks < 2 then
    return lines
  end

  local dropped = {}
  for block = 1, #blocks - 1 do
    for line = blocks[block].first, blocks[block].last do
      dropped[line] = true
    end
  end

  local kept = {}
  for row, text in ipairs(lines) do
    if not dropped[row] then
      table.insert(kept, text)
    end
  end
  return kept
end

---Write the current state of a tracked chat to disk
---@param chat CodeCompanion.Chat
---@return boolean ok
local function write_session(chat)
  local entry = sessions[chat.id]
  if not entry then
    return false
  end

  local session = serializer.to_session(chat, {
    created_at = entry.created_at,
    saved_at = os.time(),
    title = chat.title or entry.title,
  })
  session.ui_lines = api.nvim_buf_is_valid(chat.bufnr) and api.nvim_buf_get_lines(chat.bufnr, 0, -1, false) or nil

  local stem = storage.stem({ created_at = entry.created_at, slug = entry.slug })
  local ok = storage.write(stem, session)
  if ok then
    log:debug("[sessions] Wrote session %s for chat %d", stem, chat.id)
  end

  return ok
end

---Start tracking a chat as a session and write it out
---@param chat CodeCompanion.Chat
---@param title string Used until the chat has a title of its own
---@return boolean ok
local function start_session(chat, title)
  local created_at = os.time()
  sessions[chat.id] = {
    created_at = created_at,
    slug = resolve_slug(chat, { title = title, created_at = created_at }),
    title = title,
  }

  if not write_session(chat) then
    sessions[chat.id] = nil
    return false
  end

  utils.fire("ChatSessionSaved", { bufnr = chat.bufnr, id = chat.id, slug = sessions[chat.id].slug })
  return true
end

---@param title string
---@return string
local function truncate_title(title)
  if #title <= MAX_TITLE_LENGTH then
    return title
  end
  local boundary = title:sub(1, MAX_TITLE_LENGTH + 1):match("^(.*)%s")
  return vim.trim(boundary or title:sub(1, MAX_TITLE_LENGTH))
end

---Fall back to the opening question when a chat has no title of its own
---@param chat CodeCompanion.Chat
---@return string|nil
local function get_title_from_message(chat)
  for _, message in ipairs(chat.messages or {}) do
    if message.role == config.constants.USER_ROLE and type(message.content) == "string" then
      local title = vim.trim(message.content:gsub("%s+", " "))
      if title ~= "" then
        return truncate_title(title)
      end
    end
  end
end

---@param chat CodeCompanion.Chat
---@return boolean
local function can_be_saved(chat)
  return M.enabled() and (not chat.adapter or chat.adapter.type == "http")
end

---@param chat CodeCompanion.Chat
---@return nil
function M.register_chat_callbacks(chat)
  chat:add_callback("on_completed", function(c)
    if not can_be_saved(c) then
      return
    end
    if sessions[c.id] then
      if continuous_save_enabled() then
        write_session(c)
      end
    elseif autosave_enabled() then
      start_session(c, get_title_from_message(c) or "Untitled")
    end
  end)

  chat:add_callback("on_closed", function(c)
    if not sessions[c.id] then
      return
    end
    if continuous_save_enabled() then
      write_session(c)
    end
    sessions[c.id] = nil
  end)
end

---@return boolean
function M.enabled()
  return config.interactions.chat.sessions.enabled
end

---Save the chat as a session
---@param chat CodeCompanion.Chat
---@param opts? { title?: string }
---@return nil
function M.save(chat, opts)
  opts = opts or {}

  if not M.enabled() then
    return utils.notify("Sessions are turned off", vim.log.levels.WARN)
  end
  if chat.adapter and chat.adapter.type ~= "http" then
    return utils.notify("Sessions only support HTTP chats", vim.log.levels.WARN)
  end

  if sessions[chat.id] then
    if opts.title and opts.title ~= "" and opts.title ~= chat.title then
      M._rename(chat, opts.title)
    end
    if write_session(chat) then
      utils.notify("Session saved: " .. sessions[chat.id].slug)
    end
    return
  end

  local function persist_with_title(title)
    if not title or title == "" then
      return
    end
    if chat.title ~= title then
      chat:set_title(title)
    end
    if start_session(chat, title) then
      utils.notify("Session saved: " .. sessions[chat.id].slug)
    end
  end

  local prefill = opts.title or chat.title
  if prefill and prefill ~= "" then
    return persist_with_title(prefill)
  end

  -- Prompt for a title if none is provided
  vim.ui.input({ prompt = " Session Title " }, function(input)
    if input == nil then
      return
    end
    persist_with_title(input)
  end)
end

---Restore a session from disk into a new chat buffer
---@param stem string
---@param opts? { buffer_context?: table }
---@return CodeCompanion.Chat|nil
function M.load(stem, opts)
  opts = opts or {}

  local saved_chat, reason = storage.read(stem)
  if not saved_chat then
    return utils.notify("This session could not be restored because " .. reason, vim.log.levels.ERROR)
  end

  local args = serializer.to_chat_args(saved_chat.chat)
  args.buffer_context = opts.buffer_context or require("codecompanion.utils.context").get(api.nvim_get_current_buf())
  args.stop_context_insertion = true
  args.title = saved_chat.meta.title

  local messages = vim.deepcopy(args.messages)

  local chat = require("codecompanion.interactions.chat").new(args)
  if not chat then
    return
  end

  -- Chat.new's renderer drops the last message, expecting a submit re-parse, so restore it here
  chat.messages = messages
  chat.cycle = saved_chat.chat.cycle or 1
  chat.context_items = saved_chat.chat.context_items or {}
  serializer.restore_tools(chat, saved_chat.chat.tools)
  chat:set_title(saved_chat.meta.title)

  -- The saved markdown already carries the context block, so replant rather than re-render
  if saved_chat.ui_lines then
    api.nvim_buf_set_lines(chat.bufnr, 0, -1, false, prune_context_blocks(saved_chat.ui_lines))
  end
  chat.context:create_folds()

  -- Opening the chat counts as a user cursor move, which would stop `follow` short
  chat.ui.cursor.moved_by_user = false
  chat.ui:follow()

  sessions[chat.id] = {
    created_at = saved_chat.meta.created_at,
    slug = (stem:gsub("^%d+T%d+%-", "")),
  }

  utils.fire("ChatSessionRestored", { bufnr = chat.bufnr, id = chat.id, stem = stem })
  return chat
end

---List every session on disk, newest first
---@return { stem: string, meta: table }[]
function M.list()
  if not M.enabled() then
    return {}
  end

  return storage.list()
end

---Format a session for display in a picker
---@param session { stem: string, meta: table }
---@return string
function M.format(session)
  local title = session.meta.title or session.stem
  if not session.meta.saved_at then
    return title
  end
  return "(" .. utils.make_relative(session.meta.saved_at) .. " ago) " .. title
end

---Pick a session from disk and restore it into a new chat buffer
---@param opts? { buffer_context?: table, on_restored?: fun(chat: CodeCompanion.Chat) }
---@return nil
function M.select(opts)
  opts = opts or {}

  local list = M.list()
  if vim.tbl_isempty(list) then
    return utils.notify("No saved sessions found", vim.log.levels.INFO)
  end

  vim.ui.select(vim.tbl_map(M.format, list), {
    prompt = "Restore Session",
    kind = "codecompanion.nvim",
  }, function(_, idx)
    if not idx then
      return
    end
    local chat = M.load(list[idx].stem, { buffer_context = opts.buffer_context })
    if chat and opts.on_restored then
      opts.on_restored(chat)
    end
  end)
end

---Rename a tracked session by moving its files on disk
---@param chat CodeCompanion.Chat
---@param new_title string
---@return nil
function M._rename(chat, new_title)
  local entry = sessions[chat.id]
  if not entry then
    return
  end

  local new_slug = resolve_slug(chat, { title = new_title, created_at = entry.created_at })
  if new_slug == entry.slug then
    chat:set_title(new_title)
    return
  end

  storage.delete(storage.stem({ created_at = entry.created_at, slug = entry.slug }))
  entry.slug = new_slug
  chat:set_title(new_title)
end

---@param chat_id number
function M.untrack(chat_id)
  sessions[chat_id] = nil
end

---@param chat_id number
---@return boolean
function M.is_tracked(chat_id)
  return sessions[chat_id] ~= nil
end

---@param chat_id number
---@return { slug: string, created_at: number, title: string }|nil
function M.get(chat_id)
  return sessions[chat_id]
end

return M
