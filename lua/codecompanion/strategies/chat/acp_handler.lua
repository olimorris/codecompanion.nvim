---Return the ACP client
local get_client = function()
  return require("codecompanion.acp")
end

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table
---@field reasoning table
---@field tools table
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
      adapter = self.chat.adapter,
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

---Handle tool call notifications
---@param tool_call table
function ACPHandler:_handle_tool_call(tool_call)
  -- TODO: Implement tool call handling
  -- This is where the complex tool execution logic would go
end

---Handle completion
---@param stop_reason string|nil
function ACPHandler:_handle_completion(stop_reason)
  if not self.chat.status or self.chat.status == "" then
    self.chat.status = "success"
  end
  self.chat:done(self.output, self.reasoning, self.tools)
end

---Handle errors
---@param error string
function ACPHandler:_handle_error(error)
  self.chat.status = "error"
  require("codecompanion.utils.log"):error("[chat::ACPHandler] Error: %s", error)
  self.chat:done(self.output)
end

return ACPHandler
