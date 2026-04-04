local config = require("codecompanion.config")
local formatter = require("codecompanion.interactions.chat.acp.formatters")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")
local watch = require("codecompanion.interactions.shared.watch")

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table<string, table> Cache of tool calls by their ID
---@field ui_state table<string, table> Cache of tool call UI states (line_number, icon_id) by tool call ID
local ACPHandler = {}

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Chat.ACPHandler
function ACPHandler.new(chat)
  local self = setmetatable({
    chat = chat,
    output = {},
    reasoning = {},
    tools = {},
    ui_state = {},
  }, { __index = ACPHandler })

  return self --[[@type CodeCompanion.Chat.ACPHandler]]
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

  if not self:ensure_session() then
    self.chat.status = "error"
    return self.chat:done(self.output)
  end

  return self:create_and_send_prompt(payload)
end

---Ensure the ACP connection is authenticated
---@return boolean
function ACPHandler:ensure_connection()
  -- If the async init already created the connection, check if it's ready
  if self.chat.acp_connection and self.chat.acp_connection:is_ready() then
    return true
  end

  if not self.chat.acp_connection then
    self.chat.acp_connection = require("codecompanion.acp").new({
      adapter = self.chat.adapter, ---@type CodeCompanion.ACPAdapter
    })
  end

  local connected = self.chat.acp_connection:connect_and_authenticate()

  if not connected then
    return false
  end

  self.chat:update_metadata()
  watch.enable()
  utils.fire("ACPConnected", { bufnr = self.chat.bufnr })

  return true
end

---Ensure a session exists on the connection or create one if required
---@return boolean success
function ACPHandler:ensure_session()
  local conn = self.chat.acp_connection
  if not conn then
    return false
  end

  if conn.session_id then
    return true
  end

  if not conn:ensure_session() then
    return false
  end

  -- Map bufnr -> session_id so completion providers can look up ACP commands for this buffer
  local acp_commands = require("codecompanion.interactions.chat.acp.commands")
  acp_commands.link_buffer_to_session(self.chat.bufnr, conn.session_id)

  self.chat:update_metadata()

  return true
end

---Transform ACP commands in messages from \command to /command
---@param messages table The messages to transform
---@return table The transformed messages
function ACPHandler:transform_acp_commands(messages)
  if not self.chat.acp_connection or not self.chat.acp_connection.session_id then
    return messages
  end

  -- Get available ACP commands for this session
  local acp_commands = require("codecompanion.interactions.chat.acp.commands")
  local commands = acp_commands.get_commands_for_session(self.chat.acp_connection.session_id)

  if #commands == 0 then
    return messages
  end

  -- Get trigger character
  local trigger = "\\"
  if config.interactions.chat.slash_commands.opts and config.interactions.chat.slash_commands.opts.acp then
    trigger = config.interactions.chat.slash_commands.opts.acp.trigger or "\\"
  end
  local escaped_trigger = vim.pesc(trigger)

  -- Transform messages by replacing each known command
  local transformed = vim.deepcopy(messages)
  for _, message in ipairs(transformed) do
    if message.content and type(message.content) == "string" then
      -- Replace \command with /command for each known ACP command
      for _, cmd in ipairs(commands) do
        local escaped_name = vim.pesc(cmd.name)

        -- Pattern with trailing space
        local pattern_space = escaped_trigger .. escaped_name .. "(%s)"
        message.content = message.content:gsub(pattern_space, "/" .. cmd.name .. "%1")

        -- Pattern at end of string or followed by non-word character
        local pattern_end = escaped_trigger .. escaped_name .. "([^%w])"
        message.content = message.content:gsub(pattern_end, "/" .. cmd.name .. "%1")

        -- Pattern at end of string
        local pattern_eol = escaped_trigger .. escaped_name .. "$"
        message.content = message.content:gsub(pattern_eol, "/" .. cmd.name)
      end
    end
  end

  return transformed
end

---Create and configure the prompt request with all handlers
---@param payload table
---@return table Request object
function ACPHandler:create_and_send_prompt(payload)
  -- Transform ACP commands before sending
  local transformed_payload = vim.deepcopy(payload)
  transformed_payload.messages = self:transform_acp_commands(payload.messages)

  return self.chat.acp_connection
    :session_prompt(transformed_payload.messages)
    :on_message_chunk(function(content)
      self:handle_message_chunk(content)
    end)
    :on_thought_chunk(function(content)
      self:handle_thought_chunk(content)
    end)
    :on_tool_call(function(tool_call)
      self:process_tool_call(tool_call)
    end)
    :on_tool_update(function(tool_call)
      self:process_tool_call(tool_call)
    end)
    :on_permission_request(function(request)
      self:handle_permission_request(request)
    end)
    :on_complete(function()
      self:handle_completion()
    end)
    :on_error(function(error)
      self:handle_error(error)
    end)
    :with_options({ bufnr = self.chat.bufnr, interaction = "chat" })
    :send()
end

---Handle incoming message chunks
---@param content string
function ACPHandler:handle_message_chunk(content)
  table.insert(self.output, content)
  self.chat:add_buf_message(
    { role = config.constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )
end

---Handle incoming thought chunks
---@param content string
function ACPHandler:handle_thought_chunk(content)
  table.insert(self.reasoning, content)
  if config.display.chat.show_reasoning then
    self.chat:add_buf_message(
      { role = config.constants.LLM_ROLE, content = content },
      { type = self.chat.MESSAGE_TYPES.REASONING_MESSAGE }
    )
  end
end

---Output tool call to the chat
---@param tool_call table
---@return nil
function ACPHandler:process_tool_call(tool_call)
  local id = tool_call.toolCallId

  log:trace("[ACP::Handler] Processing tool call %s", tool_call)

  local merged = merge_tool_call(self.tools[id], tool_call)
  tool_call = merged

  local ok, content = pcall(formatter.tool_message, tool_call, self.chat.adapter)
  if not ok then
    content = "[Error formatting tool output]"
  end

  -- Cache or cleanup
  if tool_call.status == "completed" then
    self.tools[id] = nil
  else
    self.tools[id] = merged
  end

  -- If the tool call has already written output to the chat buffer, update the
  -- existing line rather than adding a new one
  local cached = self.ui_state[id]
  if cached then
    local update_ok, _, new_icon_id = pcall(
      self.chat.update_buf_line,
      self.chat,
      cached.line_number,
      content,
      { status = tool_call.status, icon_id = cached.icon_id, priority = 120, virt_text_pos = "inline" }
    )

    if update_ok then
      if tool_call.status == "completed" then
        self.ui_state[id] = nil
      elseif new_icon_id then
        cached.icon_id = new_icon_id
      end
      return
    end

    if tool_call.status == "completed" then
      self.ui_state[id] = nil
    end
    log:debug("[ACP::Handler] Failed to update tool call line for toolCallId %s", id)
  end

  table.insert(self.output, content)
  local line_number, icon_id = self.chat:add_buf_message({
    role = config.constants.LLM_ROLE,
    content = content,
  }, {
    status = tool_call.status or "in_progress",
    virt_text_pos = "inline",
    tools = { call_id = id },
    kind = tool_call.kind,
    type = self.chat.MESSAGE_TYPES.TOOL_MESSAGE,
  })

  self.ui_state[id] = { line_number = line_number, icon_id = icon_id }
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

  log:debug("[ACPHandler::handle_permission_request] Asking for approval")

  return require("codecompanion.interactions.chat.acp.request_permission").confirm(self.chat, request)
end

---Handle completion
function ACPHandler:handle_completion()
  if not self.chat.status or self.chat.status == "" then
    self.chat.status = "success"
  end

  self.chat:done(self.output, self.reasoning, {})
end

---Handle errors
---@param error string
function ACPHandler:handle_error(error)
  self.chat.status = "error"
  log:error("[ACP::Handler] %s", error)

  self.chat:add_buf_message(
    { role = config.constants.LLM_ROLE, content = string.format("````txt\n%s\n````", error) },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )

  self.chat:done(self.output)
end

return ACPHandler
