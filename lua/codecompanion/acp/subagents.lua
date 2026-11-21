local METHODS = require("codecompanion.acp.methods")
local log = require("codecompanion.utils.log")

local SESSION_MESSAGE_UPDATES = { session_message = true, session_message_chunk = true }

---@class CodeCompanion.ACP.Subagent
---@field id string
---@field parent_id string
---@field additionalDirectories? string[]
---@field capabilities? { cancel?: table }
---@field cwd? string
---@field description? string
---@field state? { error?: table, state: string, stopReason?: string }
---@field title? string

---@class CodeCompanion.ACP.Subagents
---@field connection CodeCompanion.ACP.Connection
---@field sessions table<string, CodeCompanion.ACP.Subagent> The subagents the agent announced, by their session ID
local Subagents = {}

---@param opts { connection: CodeCompanion.ACP.Connection }
---@return CodeCompanion.ACP.Subagents
function Subagents.new(opts)
  local self = setmetatable({ connection = opts.connection, sessions = {} }, { __index = Subagents })
  ---@cast self CodeCompanion.ACP.Subagents
  return self
end

---Copy an update's fields onto a record, leaving an omitted field unchanged and clearing one sent as null
---@param opts { record: table, update: table, fields: string[] }
---@return nil
function Subagents.patch(opts)
  for _, field in ipairs(opts.fields) do
    if opts.update[field] == vim.NIL then
      opts.record[field] = nil
    elseif opts.update[field] ~= nil then
      opts.record[field] = opts.update[field]
    end
  end
end

---@return table
local function get_chat_ui()
  return require("codecompanion.interactions.chat.acp.subagents")
end

---Check if a session is the connection's session or a subagent descended from it
---@param session_id? string
---@return boolean
function Subagents:is_known(session_id)
  if session_id == nil then
    return false
  end
  if session_id == self.connection.session_id then
    return true
  end
  local subagent = self.sessions[session_id]
  return subagent ~= nil and self:is_known(subagent.parent_id)
end

---Handle a session update that concerns subagents, returning false for one the parent's turn should handle
---Ref: https://agentclientprotocol.com/rfds/subagents
---@param opts { session_id: string, update: table, is_replayed?: boolean }
---@return boolean
function Subagents:handle(opts)
  local update = opts.update
  if update.sessionUpdate == "subagent_update" then
    self:_upsert(opts)
    return true
  end

  local is_parent_message = opts.session_id == self.connection.session_id
    and SESSION_MESSAGE_UPDATES[update.sessionUpdate] ~= nil
  if not self.sessions[opts.session_id] and not is_parent_message then
    return false
  end
  if self.connection.chat then
    get_chat_ui().handle_session_update(self.connection.chat, { session_id = opts.session_id, update = update })
  end
  return true
end

---Register or patch a subagent that a known session announced
---@param opts { session_id: string, update: table, is_replayed?: boolean }
---@return nil
function Subagents:_upsert(opts)
  local parent_id, update = opts.session_id, opts.update
  local child_id = update.sessionId
  if type(child_id) ~= "string" or child_id == self.connection.session_id or not self:is_known(parent_id) then
    return
  end

  local subagent = self.sessions[child_id]
  if subagent and subagent.parent_id ~= parent_id then
    return log:warn("[acp] Ignoring a subagent_update that moves %s to another parent", child_id)
  end

  subagent = subagent or { id = child_id, parent_id = parent_id }
  local fields = { "title", "description", "cwd", "additionalDirectories" }
  -- session/load replays history, so its capabilities and state aren't current and can't permit a cancel
  if not opts.is_replayed then
    vim.list_extend(fields, { "capabilities", "state" })
  end
  Subagents.patch({ record = subagent, update = update, fields = fields })
  self.sessions[child_id] = subagent

  if self.connection.chat then
    get_chat_ui().update(self.connection.chat, { subagent = subagent })
  end
  local state = subagent.state
  if type(state) == "table" and state.state == "idle" and state.stopReason == "cancelled" then
    self:_handle_cancelled(child_id)
  end
end

---Answer a cancelled subagent's permission requests and show its unfinished tool calls as cancelled
---@param session_id string
---@return nil
function Subagents:_handle_cancelled(session_id)
  self.connection:cancel_permission_requests(session_id)
  if self.connection.chat then
    get_chat_ui().cancel(self.connection.chat, { session_id = session_id })
  end
end

---@param session_id string
---@return boolean
function Subagents:can_cancel(session_id)
  local subagent = self.sessions[session_id]
  local capabilities = subagent and subagent.capabilities
  return type(capabilities) == "table" and type(capabilities.cancel) == "table"
end

---Cancel a subagent's current work, if the agent allows the client to
---@param session_id string
---@return boolean
function Subagents:cancel(session_id)
  if not self:can_cancel(session_id) then
    return false
  end
  self.connection:send_notification(METHODS.SESSION_CANCEL, { sessionId = session_id })
  self:_handle_cancelled(session_id)
  return true
end

---Drop every subagent, so the chat stops presenting their work state as current
---@param opts? { is_disconnected?: boolean }
---@return nil
function Subagents:forget(opts)
  self.sessions = {}
  if self.connection.chat then
    get_chat_ui().invalidate(self.connection.chat, opts)
  end
end

return Subagents
