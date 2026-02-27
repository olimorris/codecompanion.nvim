local config = require("codecompanion.config")
local formatter = require("codecompanion.interactions.chat.acp.formatters")
local log = require("codecompanion.utils.log")

-- Keep a record of UI changes in the chat buffer

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table<string, table> Cache of tool calls by their ID
---@field completed_tools table<string, table> Completed tool calls keyed by ID, tracked for message history
local ACPHandler = {}

local ACPHandlerUI = {} -- Cache of tool call UI states by chat buffer

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Chat.ACPHandler
function ACPHandler.new(chat)
  local self = setmetatable({
    chat = chat,
    output = {},
    reasoning = {},
    tools = {},
    completed_tools = {},
  }, { __index = ACPHandler })

  ACPHandlerUI[chat.bufnr] = {}

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

---@param tool_call table
---@return boolean
local function is_tool_finished(tool_call)
  return tool_call.status == "completed" or tool_call.status == "failed"
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

    -- Map bufnr -> session_id so completion providers can look up ACP commands for this buffer
    if self.chat.acp_connection.session_id then
      local acp_commands = require("codecompanion.interactions.chat.acp.commands")
      acp_commands.link_buffer_to_session(self.chat.bufnr, self.chat.acp_connection.session_id)
    end

    self.chat:update_metadata()
  end
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
  local config = require("codecompanion.config")
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
    :with_options({ bufnr = self.chat.bufnr, interaction = "chat" })
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

---Extract full text content from a ContentBlock without sanitization
---@param block table|nil
---@return string|nil
local function extract_full_text(block)
  if not block or type(block) ~= "table" then
    return nil
  end
  if block.type == "text" and type(block.text) == "string" then
    return block.text
  end
  if block.type == "resource_link" and type(block.uri) == "string" then
    return ("[resource: %s]"):format(block.uri)
  end
  if block.type == "resource" and block.resource then
    if type(block.resource.text) == "string" then
      return block.resource.text
    end
    if type(block.resource.uri) == "string" then
      return ("[resource: %s]"):format(block.resource.uri)
    end
  end
  return nil
end

---Build full tool output content for inclusion in self.messages
---@param tool_call table The completed ACP tool call
---@return string|nil The content string, or nil if no content
local function build_tool_output_message(tool_call)
  local content_parts = {}

  -- Extract full content from the content blocks
  if tool_call.content and type(tool_call.content) == "table" then
    for _, c in ipairs(tool_call.content) do
      if c.type == "content" and c.content then
        local text = extract_full_text(c.content)
        if text and text ~= "" then
          table.insert(content_parts, text)
        end
      elseif c.type == "diff" then
        local path = c.path or "file"
        table.insert(content_parts, ("Edited %s"):format(path))
      end
    end
  end

  -- Fall back to rawOutput if no content blocks
  if #content_parts == 0 and tool_call.rawOutput then
    local raw = tool_call.rawOutput
    if type(raw) == "table" then
      -- Try common rawOutput fields from different agents
      local text = raw.formatted_output or raw.aggregated_output or raw.output or raw.text or raw.message or raw.stdout
      if type(text) == "string" and text ~= "" then
        table.insert(content_parts, text)
      elseif raw.content and type(raw.content) == "table" then
        for _, block in ipairs(raw.content) do
          if type(block) == "table" and block.text then
            table.insert(content_parts, block.text)
          end
        end
      end
    elseif type(raw) == "string" and raw ~= "" then
      table.insert(content_parts, raw)
    end
  end

  if #content_parts == 0 then
    return nil
  end

  return table.concat(content_parts, "\n")
end

---@param value any
---@return string
local function encode_json(value)
  local ok, encoded = pcall(vim.json.encode, value)
  if ok and type(encoded) == "string" then
    return encoded
  end

  return "{}"
end

---Output tool call to the chat
---@param tool_call table
---@return nil
function ACPHandler:process_tool_call(tool_call)
  -- Cache the tool call to handle processing later on, such as a later permission request
  local id = tool_call.toolCallId or "unknown"

  local prev = self.tools[id]
  local merged = merge_tool_call(prev, tool_call)
  tool_call = merged or tool_call

  local ok, content = pcall(formatter.tool_message, tool_call, self.chat.adapter)
  if not ok then
    content = "[Error formatting tool output]"
  end

  -- Track completed tool calls for message history
  if is_tool_finished(tool_call) then
    self.completed_tools[id] = vim.deepcopy(tool_call)
    self.tools[id] = nil
  else
    self.tools[id] = merged
  end

  -- If the tool call has already written output to the chat buffer, then we can
  -- update it rather than adding a new line. We do this by keeping track in
  -- a global cache, segmented by chat buffer and tool call IDs
  if ACPHandlerUI[self.chat.bufnr][id] then
    local match = ACPHandlerUI[self.chat.bufnr][id]
    -- Whilst I've tried to account for all types of ACP tool output, I'm taking
    -- a cautious approach and wrapping line updates. Any failures and we'll
    -- just write the tool output onto a new line in the chat buffer
    ok, _ = pcall(function()
      self.chat:update_buf_line(
        match.line_number,
        content,
        { status = tool_call.status, icon_id = match.icon_id, priority = 120, virt_text_pos = "inline" }
      )
    end)

    -- Cleanup the cache
    if is_tool_finished(tool_call) then
      ACPHandlerUI[self.chat.bufnr][id] = nil
    end

    if ok then
      -- When a tool completes, write its full output as a foldable block
      if is_tool_finished(tool_call) then
        local full_output = build_tool_output_message(tool_call)
        if full_output and full_output ~= "" then
          local title = formatter.enhanced_title(formatter.normalize_tool_call(tool_call))
          self.chat:add_buf_message({
            role = config.constants.LLM_ROLE,
            content = full_output,
          }, {
            type = self.chat.MESSAGE_TYPES.TOOL_MESSAGE,
            title = title,
          })
        end
      end

      return
    end
    log:debug("[ACP::Handler] Failed to update tool call line for toolCallId %s", tool_call.toolCallId)
  end

  table.insert(self.output, content)
  local line_number = self.chat:add_buf_message({
    role = config.constants.LLM_ROLE,
    content = content,
  }, {
    status = tool_call.status or "in_progress",
    virt_text_pos = "inline",
    tools = { call_id = id },
    kind = tool_call.kind,
    type = self.chat.MESSAGE_TYPES.TOOL_MESSAGE,
  })

  -- When a tool call completes immediately (no prior UI entry), also write its output
  if is_tool_finished(tool_call) then
    local full_output = build_tool_output_message(tool_call)
    if full_output and full_output ~= "" then
      local title = formatter.enhanced_title(formatter.normalize_tool_call(tool_call))
      self.chat:add_buf_message({
        role = config.constants.LLM_ROLE,
        content = full_output,
      }, {
        type = self.chat.MESSAGE_TYPES.TOOL_MESSAGE,
        title = title,
      })
    end
    ACPHandlerUI[self.chat.bufnr][id] = nil

    return
  end

  ACPHandlerUI[self.chat.bufnr][id] = { line_number = line_number }
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

  return require("codecompanion.interactions.chat.acp.request_permission").show(self.chat, request)
end

---Handle completion
---@param stop_reason string|nil
function ACPHandler:handle_completion(stop_reason)
  if not self.chat.status or self.chat.status == "" then
    self.chat.status = "success"
  end
  -- Record completed tool calls in self.messages
  for id, tool_call in pairs(self.completed_tools) do
    local function_call = {
      id = id,
      type = "function",
      ["function"] = {
        name = tool_call.kind or "tool",
        arguments = encode_json(tool_call.rawInput or {}),
      },
    }

    -- Add LLM message with tool call info
    self.chat:add_message({
      role = config.constants.LLM_ROLE,
      content = "",
      tool_calls = { function_call },
    }, { visible = false })

    -- Add tool output message via adapter formatter
    local output_content = build_tool_output_message(tool_call)
    if output_content and output_content ~= "" then
      self.chat:add_tool_output({ function_call = function_call }, output_content, "")
    end

    self.completed_tools[id] = nil
  end

  self.chat:done(self.output, self.reasoning, {})
end

---Handle errors
---@param error string
function ACPHandler:handle_error(error)
  self.chat.status = "error"
  log:error("[ACP::Handler] %s", error)

  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = string.format("````txt\n%s\n````", error) },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )

  self.chat:done(self.output)
end

return ACPHandler
