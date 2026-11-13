local async = require("codecompanion.utils.async")
local config = require("codecompanion.config")
local sessions = require("codecompanion.interactions.chat.sessions")
local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.Resume: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommand
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Is the slash command enabled?
---@param chat CodeCompanion.Chat
---@return boolean,string
function SlashCommand.enabled(chat)
  -- HTTP chats resume from the sessions we persist ourselves
  if not chat.acp_connection then
    return true, ""
  end

  if not chat.acp_connection:can_list_sessions() then
    return false, "This agent does not support listing sessions"
  end

  if not chat.acp_connection:can_load_session() then
    return false, "This agent does not support loading sessions"
  end

  return true, ""
end

---Format a session for display in the picker
---@param session table SessionInfo
---@return string
local function format_session(session)
  local parts = {}

  if session.updatedAt then
    local ts = utils.timestamp_from_iso(session.updatedAt)
    if ts then
      table.insert(parts, "(" .. utils.make_relative(ts) .. ")")
    end
  end

  if session.title then
    table.insert(parts, session.title)
  else
    table.insert(parts, session.sessionId)
  end

  return table.concat(parts, " ")
end

---@param chat CodeCompanion.Chat
---@return boolean
local function has_user_messages(chat)
  return vim.iter(chat.messages):any(function(message)
    return message.role == config.constants.USER_ROLE and message.content ~= ""
  end)
end

---@param chat CodeCompanion.Chat
---@param selected table The session the user picked
---@return nil
local function load_session(chat, selected)
  local updates = {}
  local ok = chat.acp_connection:load_session(selected.sessionId, {
    on_session_update = function(update)
      table.insert(updates, update)
    end,
  })

  if ok then
    local acp_commands = require("codecompanion.interactions.chat.acp.commands")
    acp_commands.link_buffer_to_session(chat.bufnr, chat.acp_connection.session_id)

    require("codecompanion.interactions.chat.acp.render").restore_session(chat, updates)

    if selected.title then
      chat:set_title(selected.title)
    end

    utils.fire("ACPChatRestored", {
      bufnr = chat.bufnr,
      id = chat.id,
      session_id = chat.acp_connection.session_id,
      title = chat.title,
    })

    utils.notify("Resumed session: " .. (selected.title or selected.sessionId), vim.log.levels.INFO)
  else
    utils.notify("Failed to load session", vim.log.levels.ERROR)
  end
end

---@param chat CodeCompanion.Chat
---@param sessions table[]
---@return nil
local function pick_session(chat, sessions)
  local choices = vim.tbl_map(format_session, sessions)

  vim.ui.select(choices, {
    prompt = "Resume Session",
    kind = "codecompanion.nvim",
  }, function(_, idx)
    if not idx then
      return
    end

    if chat.current_request then
      return utils.notify("A session can't be resumed while a request is in progress", vim.log.levels.WARN)
    end

    load_session(chat, sessions[idx])
  end)
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local Chat = self.Chat

  if not Chat.acp_connection then
    return sessions.select({
      on_restored = function()
        if not has_user_messages(Chat) then
          Chat:close()
        end
      end,
    })
  end

  if Chat.cycle > 1 then
    return utils.notify("The /resume command must be called before submitting any messages", vim.log.levels.WARN)
  end

  if not Chat.acp_connection then
    return utils.notify("No ACP connection available", vim.log.levels.WARN)
  end

  -- Inside a coroutine the connection yields for the agent's reply, rather than blocking the editor
  async.sync(function()
    local listed = Chat.acp_connection:session_list({
      max_sessions = (self.config.opts and self.config.opts.max_sessions) or 500,
    })

    if #listed == 0 then
      return utils.notify("No previous sessions found", vim.log.levels.INFO)
    end

    -- Scheduled so the load runs outside this coroutine and blocks, keeping the user from submitting over it
    vim.schedule(function()
      pick_session(Chat, listed)
    end)
  end)()
end

return SlashCommand
