--=============================================================================
-- ACP Commands Storage
-- Manages available commands from ACP agents per session
--=============================================================================

local log = require("codecompanion.utils.log")

---@class CodeCompanion.ACP.Commands
local ACPCommands = {}

-- Storage: session_id -> list of available commands
---@type table<string, ACP.availableCommands>
local commands_by_session = {}

-- Storage: bufnr -> session_id mapping
---@type table<number, string>
local buffer_sessions = {}

---Register available commands for a session
---@param session_id string
---@param commands ACP.availableCommands
---@return nil
function ACPCommands.register_commands(session_id, commands)
  if not session_id or type(commands) ~= "table" then
    return log:error("[acp::commands] Invalid arguments to register_commands")
  end

  commands_by_session[session_id] = commands
  log:debug("[acp::commands] Registered %d commands for session %s", #commands, session_id)

  -- Fire event to notify completion providers
  vim.schedule(function()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeCompanionACPCommandsUpdate",
      data = { session_id = session_id, commands = commands },
    })
  end)
end

---Link a buffer to a session
---@param bufnr number
---@param session_id string
---@return nil
function ACPCommands.link_buffer_to_session(bufnr, session_id)
  buffer_sessions[bufnr] = session_id
  log:trace("[acp::commands] Linked buffer %d to session %s", bufnr, session_id)
end

---Unlink a buffer from its session
---@param bufnr number
---@return nil
function ACPCommands.unlink_buffer(bufnr)
  local session_id = buffer_sessions[bufnr]
  buffer_sessions[bufnr] = nil
  log:trace("[acp::commands] Unlinked buffer %d (was session %s)", bufnr, session_id or "nil")
end

---Get commands for a specific session
---@param session_id string
---@return ACP.availableCommands
function ACPCommands.get_commands_for_session(session_id)
  return commands_by_session[session_id] or {}
end

---Get commands for a buffer
---@param bufnr number
---@return ACP.availableCommands
function ACPCommands.get_commands_for_buffer(bufnr)
  local session_id = buffer_sessions[bufnr]
  if not session_id then
    return {}
  end
  return ACPCommands.get_commands_for_session(session_id)
end

---Clear commands for a session
---@param session_id string
---@return nil
function ACPCommands.clear_session(session_id)
  commands_by_session[session_id] = nil
  log:trace("[acp::commands] Cleared commands for session %s", session_id)
end

---Clear all commands (useful for testing)
---@return nil
function ACPCommands.clear_all()
  commands_by_session = {}
  buffer_sessions = {}
  log:trace("[acp::commands] Cleared all commands")
end

-- Cleanup when chat is closed (not on BufDelete, which can fire spuriously during completion)
local aug = vim.api.nvim_create_augroup("codecompanion.acp.commands", { clear = true })
vim.api.nvim_create_autocmd("User", {
  group = aug,
  pattern = "CodeCompanionChatClosed",
  callback = function(args)
    ACPCommands.unlink_buffer(args.data.bufnr)
  end,
})

return ACPCommands
