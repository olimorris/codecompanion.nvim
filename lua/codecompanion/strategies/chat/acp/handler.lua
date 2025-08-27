local config = require("codecompanion.config")
local formatter = require("codecompanion.strategies.chat.acp.formatters")

---Return the ACP client
---@return CodeCompanion.ACP.Connection
local get_client = function()
  return require("codecompanion.acp")
end

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table Tools currently being used by the Agent
local ACPHandler = {}

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Chat.ACPHandler
function ACPHandler.new(chat)
  local self = setmetatable({
    chat = chat,
    output = {},
    reasoning = {},
    tools = {},
  }, { __index = ACPHandler })

  return self --[[@type CodeCompanion.Chat.ACPHandler]]
end

---Submit payload to ACP and handle streaming response
---@param payload table The payload to send to the LLM
---@return table|nil Request object or nil on error
function ACPHandler:submit(payload)
  if not self:_ensure_connection() then
    self.chat.status = "error"
    return self.chat:done(self.output)
  end

  return self:_create_prompt_request(payload)
end

---Ensure ACP connection is established
---@return boolean success
function ACPHandler:_ensure_connection()
  if not self.chat.acp_connection then
    self.chat.acp_connection = get_client().new({
      adapter = self.chat.adapter, --[[@type CodeCompanion.ACPAdapter]]
    })

    local connected = self.chat.acp_connection:connect()
    if not connected then
      return false
    end
  end
  return true
end

---Create and configure the prompt request with all handlers
---@param payload table
---@return table Request object
function ACPHandler:_create_prompt_request(payload)
  return self.chat.acp_connection
    :prompt(payload.messages)
    :on_message_chunk(function(content)
      self:_handle_message_chunk(content)
    end)
    :on_thought_chunk(function(content)
      self:_handle_thought_chunk(content)
    end)
    :on_tool_call(function(tool_call)
      self:_handle_tool_call(tool_call)
    end)
    :on_tool_update(function(tool_update)
      self:_handle_tool_update(tool_update)
    end)
    :on_permission_request(function(request)
      self:_handle_permission_request(request)
    end)
    :on_complete(function(stop_reason)
      self:_handle_completion(stop_reason)
    end)
    :on_error(function(error)
      self:_handle_error(error)
    end)
    :with_options({ bufnr = self.chat.bufnr, strategy = "chat" })
    :send()
end

---Handle incoming message chunks
---@param content string
function ACPHandler:_handle_message_chunk(content)
  table.insert(self.output, content)
  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )
end

---Handle incoming thought chunks
---@param content string
function ACPHandler:_handle_thought_chunk(content)
  table.insert(self.reasoning, content)
  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.REASONING_MESSAGE }
  )
end

---Output tool call to the chat
---@param tool_call table
---@return nil
function ACPHandler:_process_tool_call(tool_call)
  local content = formatter.tool_message(tool_call)

  if tool_call.status == "completed" then
    self.tools[tool_call.toolCallId] = nil
  else
    self.tools[tool_call.toolCallId] = {
      status = tool_call.status,
      title = ("`" .. (tool_call.title or "Tool Call") .. "`"),
      kind = tool_call.kind,
    }
  end

  table.insert(self.output, content)
  self.chat:add_buf_message({
    role = config.constants.LLM_ROLE,
    content = content,
  }, {
    status = tool_call.status,
    tool_call_id = tool_call.toolCallId,
    kind = tool_call.kind,
    type = self.chat.MESSAGE_TYPES.TOOL_MESSAGE,
  })
end

---Handle tool call notifications
---@param tool_call table
function ACPHandler:_handle_tool_call(tool_call)
  return self:_process_tool_call(tool_call)
end

---Handle tool call updates and their respective status
---@param tool_call table
function ACPHandler:_handle_tool_update(tool_call)
  return self:_process_tool_call(tool_call)
end

---Handle permission requests from the agent
---@param request table
---@return nil
function ACPHandler:_handle_permission_request(request)
  return require("codecompanion.strategies.chat.acp.request_permission").show(self.chat, request)
end

---Handle completion
---@param stop_reason string|nil
function ACPHandler:_handle_completion(stop_reason)
  if not self.chat.status or self.chat.status == "" then
    self.chat.status = "success"
  end
  self.chat:done(self.output, self.reasoning, {})
end

---Handle errors
---@param error string
function ACPHandler:_handle_error(error)
  self.chat.status = "error"
  require("codecompanion.utils.log"):error("[chat::ACPHandler] Error: %s", error)
  self.chat:done(self.output)
end

return ACPHandler
