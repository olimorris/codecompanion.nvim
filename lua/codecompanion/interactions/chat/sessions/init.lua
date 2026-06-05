---Persistent chat sessions.
---
---Lives outside the Chat class; interacts with it through:
---  - `chat:snapshot()` for state reads (the only supported read seam)
---  - `chat:add_callback()` for `on_completed` / `on_closed` lifecycle hooks
---  - `Chat.new()` for restoration
---
---Chat has no knowledge of sessions. Tracking state (which chat is being
---auto-saved under which slug) lives here, keyed by chat id.

local log = require("codecompanion.utils.log")
local serializer = require("codecompanion.interactions.chat.sessions.serializer")
local slug_utils = require("codecompanion.interactions.chat.sessions.slug")
local storage = require("codecompanion.interactions.chat.sessions.storage")
local utils = require("codecompanion.utils")

local api = vim.api

local M = {}

---Per-chat tracking. Indexed by `chat.id`.
---@type table<number, { slug: string, created_at: string, autosave: boolean }>
local sessions = {}

---@return string
local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ") --[[@as string]]
end

---@param chat CodeCompanion.Chat
---@param title string
---@return string slug
local function resolve_slug(chat, title)
  local base = slug_utils.slugify(title)
  local current = sessions[chat.id] and sessions[chat.id].slug
  return slug_utils.disambiguate(base, storage.exists, current)
end

---Write the current state of a tracked chat to disk.
---@param chat CodeCompanion.Chat
---@return boolean ok
local function write_session(chat)
  local entry = sessions[chat.id]
  if not entry then
    return false
  end

  local snapshot = chat:snapshot()
  local data = serializer.encode(snapshot, {
    slug = entry.slug,
    created_at = entry.created_at,
    updated_at = now_iso(),
  })

  local ui_lines = api.nvim_buf_is_valid(chat.bufnr) and api.nvim_buf_get_lines(chat.bufnr, 0, -1, false) or nil

  local ok = storage.write(entry.slug, data, ui_lines)
  if ok then
    log:debug("[sessions] Wrote session %s for chat %d", entry.slug, chat.id)
  end
  return ok
end

---Attach the auto-save callbacks to a chat.
---@param chat CodeCompanion.Chat
local function attach_autosave(chat)
  chat:add_callback("on_completed", function(c)
    if sessions[c.id] and sessions[c.id].autosave then
      write_session(c)
    end
  end)
  chat:add_callback("on_closed", function(c)
    if sessions[c.id] and sessions[c.id].autosave then
      write_session(c)
      sessions[c.id] = nil
    end
  end)
end

---Save the chat as a session. On first call, prompts for a title if the chat
---has none; subsequent calls just write to disk.
---@param chat CodeCompanion.Chat
---@param opts? { title?: string }
---@return nil
function M.save(chat, opts)
  opts = opts or {}

  if chat.adapter and chat.adapter.type ~= "http" then
    return utils.notify("Sessions only support HTTP chats", vim.log.levels.WARN)
  end

  -- Existing tracked session: just rewrite under the current slug.
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

    local slug = resolve_slug(chat, title)
    sessions[chat.id] = {
      autosave = true,
      created_at = now_iso(),
      slug = slug,
    }
    attach_autosave(chat)

    if write_session(chat) then
      utils.notify("Session saved: " .. slug)
      utils.fire("ChatSessionSaved", { bufnr = chat.bufnr, id = chat.id, slug = slug })
    end
  end

  local prefill = opts.title or chat.title
  if prefill and prefill ~= "" then
    return persist_with_title(prefill)
  end

  vim.ui.input({ prompt = " Session Title " }, function(input)
    if input == nil then
      return
    end
    persist_with_title(input)
  end)
end

---Rename a tracked session by moving its files on disk.
---@param chat CodeCompanion.Chat
---@param new_title string
---@return nil
function M._rename(chat, new_title)
  local entry = sessions[chat.id]
  if not entry then
    return
  end

  local new_slug = resolve_slug(chat, new_title)
  if new_slug == entry.slug then
    chat:set_title(new_title)
    return
  end

  -- Delete old files; the next write under new_slug creates fresh ones.
  storage.delete(entry.slug)
  entry.slug = new_slug
  chat:set_title(new_title)
end

---Disable auto-save for a chat (e.g. after `/fork` produces a new chat).
---@param chat_id number
function M.untrack(chat_id)
  sessions[chat_id] = nil
end

---Whether a chat is currently being tracked for auto-save.
---@param chat_id number
---@return boolean
function M.is_tracked(chat_id)
  return sessions[chat_id] ~= nil
end

---@param chat_id number
---@return { slug: string, created_at: string, autosave: boolean }|nil
function M.get(chat_id)
  return sessions[chat_id]
end

return M
