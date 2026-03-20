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
  if not chat.acp_connection then
    return false, "The resume slash command requires an ACP connection"
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
    local ts = utils.parse_iso8601(session.updatedAt)
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

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local Chat = self.Chat

  if Chat.cycle > 1 then
    return utils.notify("The /resume command must be called before submitting any messages", vim.log.levels.WARN)
  end

  if not Chat.acp_connection then
    return utils.notify("No ACP connection available", vim.log.levels.WARN)
  end

  local sessions = Chat.acp_connection:session_list({
    max_sessions = (self.config.opts and self.config.opts.max_sessions) or 500,
  })

  if #sessions == 0 then
    return utils.notify("No previous sessions found", vim.log.levels.INFO)
  end

  local choices = {}
  local session_map = {}
  for i, session in ipairs(sessions) do
    table.insert(choices, format_session(session))
    session_map[i] = session
  end

  vim.ui.select(choices, {
    prompt = "Resume Session",
    kind = "codecompanion.nvim",
  }, function(_, idx)
    if not idx then
      return
    end

    local selected = session_map[idx]

    -- Collect all session updates during the synchronous load
    local updates = {}
    local ok = Chat.acp_connection:load_session(selected.sessionId, {
      on_session_update = function(update)
        table.insert(updates, update)
      end,
    })

    if ok then
      local acp_commands = require("codecompanion.interactions.chat.acp.commands")
      acp_commands.link_buffer_to_session(Chat.bufnr, Chat.acp_connection.session_id)

      require("codecompanion.interactions.chat.acp.render").restore_session(Chat, updates)

      if selected.title then
        Chat:set_title(selected.title)
      end

      utils.notify("Resumed session: " .. (selected.title or selected.sessionId), vim.log.levels.INFO)
    else
      utils.notify("Failed to load session", vim.log.levels.ERROR)
    end
  end)
end

return SlashCommand
