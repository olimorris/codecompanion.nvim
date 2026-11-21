local Queue = require("codecompanion.utils.queue")
local utils = require("codecompanion.utils")

---@class CodeCompanion.Chat.ACPPermissions
---@field chat CodeCompanion.Chat
---@field queue CodeCompanion.Queue
---@field active boolean
---@field request? table The request the user is being asked about
---@field respond? function The active request's original respond, which answers the agent directly
local Permissions = {}

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Chat.ACPPermissions
function Permissions.new(chat)
  local self = setmetatable({ chat = chat, active = false, queue = Queue.new() }, { __index = Permissions })
  ---@cast self CodeCompanion.Chat.ACPPermissions
  return self
end

---Queue a permission request, asking the user once they've answered the ones before it
---@param request table
---@return nil
function Permissions:push(request)
  self.queue:push(request)
  self:_present_next()
end

---Pop the next request that still awaits an answer
---@return table|nil
function Permissions:_pop_pending()
  local request = self.queue:pop()
  -- A cancelled subagent has its requests answered while they wait in the queue
  while request and not request.is_pending() do
    request = self.queue:pop()
  end
  return request
end

---Fill in a request's tool call from the one the agent announced, so the diff UI can activate
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
local function hydrate_tool_call(chat, request)
  local merge_tool_call = require("codecompanion.interactions.chat.acp.handler").merge_tool_call
  local tool_call = request.tool_call
  if type(tool_call) ~= "table" or not tool_call.toolCallId then
    return
  end

  -- A tool call ID is only unique within its session, so a subagent's request looks up the subagent's own calls
  local subagent = chat.subagents[request.session_id]
  local cached_calls = subagent and subagent.tool_calls or chat.tool_calls.acp
  local cached = cached_calls[tool_call.toolCallId]
  if cached and (tool_call.content == nil or tool_call.content == vim.NIL) then
    request.tool_call = merge_tool_call({ existing = cached, incoming = tool_call })
  end

  -- The permission request can carry details the announcement lacked, such as the `rawInput` being approved
  if not subagent then
    chat.tool_calls.acp[tool_call.toolCallId] =
      merge_tool_call({ existing = chat.tool_calls.acp[tool_call.toolCallId], incoming = request.tool_call })
  end
end

---Ask the user about the next queued request, unless they're already answering one
---@return nil
function Permissions:_present_next()
  if self.active then
    return
  end
  local request = self:_pop_pending()
  if not request then
    return
  end
  self.active = true
  self.request = request
  self.respond = request.respond
  hydrate_tool_call(self.chat, request)

  local send_response = request.respond
  request.respond = function(option_id, cancelled)
    if self.request ~= request then
      return
    end
    send_response(option_id, cancelled)
    self:_release()
    self:_present_next()
  end

  return require("codecompanion.interactions.chat.acp.request_permission").confirm(self.chat, request)
end

---@return nil
function Permissions:_release()
  self.active = false
  self.request = nil
  self.respond = nil
end

---Cancel the requests the turn left unanswered, keeping those of subagents that may still be working
---@return nil
function Permissions:cancel_turn()
  local is_subagent_request = function(request)
    return self.chat.subagents[request.session_id] ~= nil
  end

  local cancelled = {}
  if self.request and not is_subagent_request(self.request) then
    table.insert(cancelled, { respond = self.respond })
    self:_release()
  end

  local queued = self.queue:contents()
  self.queue = Queue.new()
  for _, request in ipairs(queued) do
    if is_subagent_request(request) then
      self.queue:push(request)
    else
      table.insert(cancelled, request)
    end
  end

  for _, request in ipairs(cancelled) do
    pcall(request.respond, nil, true)
  end
  if #cancelled > 0 then
    utils.fire("ToolApprovalFinished", { bufnr = self.chat.bufnr, choice = "cancelled" })
  end

  self:_present_next()
end

return Permissions
