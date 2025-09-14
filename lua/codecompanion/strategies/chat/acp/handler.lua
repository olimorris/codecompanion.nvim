local config = require("codecompanion.config")
local formatter = require("codecompanion.strategies.chat.acp.formatters")

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table<string, table> Cache of tool calls by their ID
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

---Return the ACP client
---@return CodeCompanion.ACP.Connection
local get_client = function()
  return require("codecompanion.acp")
end

---Merge an incoming tool call/update into the cache
---@param existing table|nil
---@param incoming table|nil
---@return table
local function merge_tool_call(existing, incoming)
  local out = vim.deepcopy(existing or {})
  for k, v in pairs(incoming or {}) do
    if v ~= vim.NIL then
      out[k] = v
    end
  end
  return out
end

---Submit payload to ACP and handle streaming response
---@param payload table The payload to send to the LLM
---@return table|nil Request object or nil on error
function ACPHandler:submit(payload)
  if not self:ensure_connection() then
    self.chat.status = "error"
    return self.chat:done(self.output)
  end

  return self:create_and_send_prompt(payload)
end

---Ensure ACP connection is established
---@return boolean success
function ACPHandler:ensure_connection()
  if not self.chat.acp_connection then
    self.chat.acp_connection = get_client().new({
      adapter = self.chat.adapter, --[[@type CodeCompanion.ACPAdapter]]
    })

    local connected = self.chat.acp_connection:connect_and_initialize()

    if not connected then
      return false
    end
  end
  return true
end

---Create and configure the prompt request with all handlers
---@param payload table
---@return table Request object
function ACPHandler:create_and_send_prompt(payload)
  return self.chat.acp_connection
    :session_prompt(payload.messages)
    :on_message_chunk(function(content)
      self:handle_message_chunk(content)
    end)
    :on_thought_chunk(function(content)
      self:handle_thought_chunk(content)
    end)
    :on_tool_call(function(tool_call)
      self:handle_tool_call(tool_call)
    end)
    :on_tool_update(function(tool_update)
      self:handle_tool_update(tool_update)
    end)
    :on_permission_request(function(request)
      self:handle_permission_request(request)
    end)
    :on_complete(function(stop_reason)
      self:handle_completion(stop_reason)
    end)
    :on_error(function(error)
      self:handle_error(error)
    end)
    :with_options({ bufnr = self.chat.bufnr, strategy = "chat" })
    :send()
end

---Handle incoming message chunks
---@param content string
function ACPHandler:handle_message_chunk(content)
  table.insert(self.output, content)
  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )
end

---Handle incoming thought chunks
---@param content string
function ACPHandler:handle_thought_chunk(content)
  table.insert(self.reasoning, content)
  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.REASONING_MESSAGE }
  )
end

---Output tool call to the chat
---@param tool_call table
---@return nil
function ACPHandler:process_tool_call(tool_call)
  -- Cache the tool call to handle processing later on, such as a later permission request
  local id = tool_call.toolCallId
  if id then
    local prev = self.tools[id]
    local merged = merge_tool_call(prev, tool_call)
    -- Drop from the cache once completed
    if tool_call.status == "completed" then
      self.tools[id] = nil
    else
      self.tools[id] = merged
    end
    tool_call = merged or tool_call
  end

  local ok, content = pcall(formatter.tool_message, tool_call)
  if not ok then
    content = "[Error formatting tool output]"
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
function ACPHandler:handle_tool_call(tool_call)
  return self:process_tool_call(tool_call)
end

---Handle tool call updates and their respective status
---@param tool_call table
function ACPHandler:handle_tool_update(tool_call)
  return self:process_tool_call(tool_call)
end

---Handle permission requests from the agent
---@param request table
---@return nil
function ACPHandler:handle_permission_request(request)
  local tool_call = request.tool_call

  if
    type(tool_call) == "table"
    and tool_call.toolCallId
    and (tool_call.content == nil or tool_call.content == vim.NIL)
  then
    local cached = self.tools[tool_call.toolCallId]
    if cached then
      -- Merge the cached tool call details into the request's tool call to enable the diff UI to activate
      request.tool_call = merge_tool_call(cached, tool_call)
    end
  end

  return require("codecompanion.strategies.chat.acp.request_permission").show(self.chat, request)
end

---Handle completion
---@param stop_reason string|nil
function ACPHandler:handle_completion(stop_reason)
  if not self.chat.status or self.chat.status == "" then
    self.chat.status = "success"
  end
  self.chat:done(self.output, self.reasoning, {})
end

---Handle errors
---@param error string
function ACPHandler:handle_error(error)
  self.chat.status = "error"
  require("codecompanion.utils.log"):error("[chat::ACPHandler] Error: %s", error)
  self.chat:done(self.output)
end

return ACPHandler
