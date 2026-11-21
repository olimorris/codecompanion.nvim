local acp = require("codecompanion.acp")
local handler = require("codecompanion.interactions.chat.acp.handler")
local prompt_builder = require("codecompanion.acp.prompt_builder")
local protocol = require("codecompanion.acp.subagents")

local M = {}

---@param content any
---@return string
local function join_text(content)
  local blocks = vim.islist(content) and content or { content }
  local texts = {}
  for _, block in ipairs(blocks) do
    local text = type(block) == "table" and prompt_builder.extract_text(block)
    if text and text ~= "" then
      table.insert(texts, text)
    end
  end
  return table.concat(texts, "")
end

---@param subagent CodeCompanion.Chat.ACPSubagent
---@param message_id string
---@return table
local function find_or_add_message(subagent, message_id)
  local message = vim.iter(subagent.transcript):find(function(item)
    return item.type == "session_message" and item.message_id == message_id
  end)
  if not message then
    message = { type = "session_message", message_id = message_id, text = "" }
    table.insert(subagent.transcript, message)
  end
  return message
end

---Append streamed text to the transcript, extending the last entry when it's of the same type
---@param subagent CodeCompanion.Chat.ACPSubagent
---@param opts { type: "message"|"thought", content: any }
---@return nil
local function append_text(subagent, opts)
  local text = join_text(opts.content)
  local last = subagent.transcript[#subagent.transcript]
  if last and last.type == opts.type then
    last.text = last.text .. text
  else
    table.insert(subagent.transcript, { type = opts.type, text = text })
  end
end

---Apply a `session_message` upsert or a `session_message_chunk` to a stored message
---@param message table
---@param opts { update: table }
---@return nil
local function apply_message_update(message, opts)
  local update = opts.update
  if update.sessionUpdate == "session_message_chunk" then
    message.text = message.text .. join_text(update.content)
    return
  end

  protocol.patch({
    record = message,
    update = update,
    fields = { "senderSessionId", "recipientSessionId", "senderMessageId", "recipientMessageId" },
  })
  if update.content == vim.NIL then
    message.text = ""
  elseif update.content ~= nil then
    message.text = join_text(update.content)
  end
end

local SESSION_UPDATES = {
  agent_message_chunk = function(subagent, update)
    append_text(subagent, { type = "message", content = update.content })
  end,
  agent_thought_chunk = function(subagent, update)
    append_text(subagent, { type = "thought", content = update.content })
  end,
  plan = function(subagent, update)
    subagent.plan = update.entries
  end,
  usage_update = function(subagent, update)
    subagent.usage = { used = update.used, size = update.size }
  end,
  tool_call = function(subagent, update)
    local id = update.toolCallId
    if not subagent.tool_calls[id] then
      table.insert(subagent.transcript, { type = "tool_call", id = id })
    end
    subagent.tool_calls[id] = handler.merge_tool_call({ existing = subagent.tool_calls[id], incoming = update })
  end,
  session_message = function(subagent, update)
    apply_message_update(find_or_add_message(subagent, update.messageId), { update = update })
  end,
  config_option_update = function(subagent, update)
    local option = vim.iter(update.configOptions or {}):find(function(item)
      return item.category == "model"
    end)
    if not option then
      subagent.model = nil
      return
    end
    local selected = vim.iter(acp.flatten_config_options(option.options or {})):find(function(item)
      return item.value == option.currentValue
    end)
    subagent.model = selected and selected.name or option.currentValue
  end,
}
SESSION_UPDATES.tool_call_update = SESSION_UPDATES.tool_call
SESSION_UPDATES.session_message_chunk = SESSION_UPDATES.session_message

---Record an update from a subagent's own session, returning false for one the transcript doesn't keep
---@param subagent CodeCompanion.Chat.ACPSubagent
---@param opts { update: table }
---@return boolean
function M.apply(subagent, opts)
  local apply_update = SESSION_UPDATES[opts.update.sessionUpdate]
  if not apply_update then
    return false
  end
  apply_update(subagent, opts.update)
  return true
end

---Record the ACP session's message to one of its subagents, returning the recipient once it's known
---@param chat CodeCompanion.Chat
---@param opts { update: table }
---@return CodeCompanion.Chat.ACPSubagent|nil
function M.apply_parent_message(chat, opts)
  local update = opts.update
  local message = chat.messages_to_subagents[update.messageId] or { message_id = update.messageId, text = "" }
  chat.messages_to_subagents[update.messageId] = message
  apply_message_update(message, { update = update })

  -- A message can stream before the agent names its recipient, so it joins a transcript once that's known
  local recipient = chat.subagents[message.recipientSessionId]
  if recipient and not message.is_listed then
    message.is_listed = true
    table.insert(recipient.transcript, { type = "parent_message", message_id = message.message_id })
  end
  return recipient
end

---@param subagent CodeCompanion.Chat.ACPSubagent
---@return nil
function M.cancel_tool_calls(subagent)
  for _, call in pairs(subagent.tool_calls) do
    if call.status ~= "completed" and call.status ~= "failed" then
      call.status = "cancelled"
    end
  end
end

return M
