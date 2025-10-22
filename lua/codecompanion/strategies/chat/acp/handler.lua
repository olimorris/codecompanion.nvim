local formatter = require("codecompanion.strategies.chat.acp.formatters")
local log = require("codecompanion.utils.log")

-- Keep a record of UI changes in the chat buffer

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table<string, table> Cache of tool calls by their ID
---@field tool_watches table<string, string> Map of tool call ID to FS monitor watch ID
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
    tool_watches = {}, -- Track FS monitor watch IDs by tool call ID
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
      local acp_commands = require("codecompanion.strategies.chat.acp.commands")
      acp_commands.link_buffer_to_session(self.chat.bufnr, self.chat.acp_connection.session_id)
    end
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
  local acp_commands = require("codecompanion.strategies.chat.acp.commands")
  local commands = acp_commands.get_commands_for_session(self.chat.acp_connection.session_id)

  if #commands == 0 then
    return messages
  end

  -- Get trigger character
  local config = require("codecompanion.config")
  local trigger = "\\"
  if config.strategies.chat.slash_commands.opts and config.strategies.chat.slash_commands.opts.acp then
    trigger = config.strategies.chat.slash_commands.opts.acp.trigger or "\\"
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

  local prev = self.tools[id]
  local merged = merge_tool_call(prev, tool_call)
  tool_call = merged or tool_call

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
    if tool_call.status == "completed" then
      ACPHandlerUI[self.chat.bufnr][id] = nil
    end

    if ok then
      return
    end
    log:debug("[ACP::Handler] Failed to update tool call line for toolCallId %s", tool_call.toolCallId)
  end

  table.insert(self.output, content)
  local line_number = self.chat:add_buf_message({
    role = require("codecompanion.config").constants.LLM_ROLE,
    content = content,
  }, {
    status = tool_call.status or "in_progress",
    virt_text_pos = "inline",
    tools = { call_id = id },
    kind = tool_call.kind,
    type = self.chat.MESSAGE_TYPES.TOOL_MESSAGE,
  })

  ACPHandlerUI[self.chat.bufnr][id] = { line_number = line_number }
end

---Extract all file paths from a tool call (locations, content, title)
---@param tool_call table
---@return string[] paths Array of file paths found
local function extract_paths_from_tool_call(tool_call)
  local paths = {}
  local seen = {}

  -- 1. Check locations array (most reliable)
  if tool_call.locations and type(tool_call.locations) == "table" then
    for _, location in ipairs(tool_call.locations) do
      if location.path and type(location.path) == "string" and not seen[location.path] then
        table.insert(paths, location.path)
        seen[location.path] = true
      end
    end
  end

  -- 2. Check content array (for diffs, edits, etc.)
  if tool_call.content and type(tool_call.content) == "table" then
    for _, content_item in ipairs(tool_call.content) do
      if content_item.path and type(content_item.path) == "string" and not seen[content_item.path] then
        table.insert(paths, content_item.path)
        seen[content_item.path] = true
      end
    end
  end

  -- 3. Try to extract from title (fallback for non-standard agents)
  if tool_call.title and type(tool_call.title) == "string" then
    -- Match patterns like "Edit `/path/to/file.txt`" or "Edit /path/to/file.txt"
    for path in tool_call.title:gmatch("`([^`]+)`") do
      if not seen[path] and vim.fn.filereadable(vim.fn.expand(path)) == 1 then
        table.insert(paths, path)
        seen[path] = true
      end
    end
    -- Try without backticks as well
    for path in tool_call.title:gmatch("%s(/[^%s]+)") do
      if not seen[path] and vim.fn.filereadable(vim.fn.expand(path)) == 1 then
        table.insert(paths, path)
        seen[path] = true
      end
    end
  end

  return paths
end

---Handle tool call notifications
---@param tool_call table
function ACPHandler:handle_tool_call(tool_call)
  -- Start global workspace monitoring if not already running
  if tool_call.toolCallId and tool_call.sessionUpdate == "tool_call" then
    if not self.chat.fs_monitor then
      local FSMonitor = require("codecompanion.strategies.chat.fs_monitor")
      self.chat.fs_monitor = FSMonitor.new(self.chat)
    end

    -- Start global workspace monitoring once
    if not self.chat.fs_monitor_watch_id then
      local cwd = vim.fn.getcwd()
      self.chat.fs_monitor_watch_id = self.chat.fs_monitor:start_monitoring("acp_workspace", cwd, {
        prepopulate = true,
        recursive = true,
      })
    end

    -- Initialize tool timing tracking
    if not self.tool_timings then
      self.tool_timings = {}
    end

    -- Record tool start time and extract paths for attribution
    local tool_name = tool_call.name or tool_call.kind or "acp_tool"
    local paths = extract_paths_from_tool_call(tool_call)

    self.tool_timings[tool_call.toolCallId] = {
      start_time = vim.uv.hrtime(),
      tool_name = tool_name,
      paths = paths,
    }
  end

  return self:process_tool_call(tool_call)
end

---Handle tool call updates and their respective status
---@param tool_call table
function ACPHandler:handle_tool_update(tool_call)
  -- Tag changes when tool completes
  if tool_call.status == "completed" or tool_call.status == "error" or tool_call.status == "rejected" then
    if self.tool_timings and tool_call.toolCallId then
      local timing = self.tool_timings[tool_call.toolCallId]

      if timing and self.chat.fs_monitor then
        local tool_end_time = vim.uv.hrtime()

        -- Create tool_args format for path validation
        local tool_args = {}
        if timing.paths and #timing.paths > 0 then
          -- Use first path as primary filepath for validation
          tool_args.filepath = timing.paths[1]
        end

        -- Tag changes made during this tool's execution
        self.chat.fs_monitor:tag_changes_in_range(timing.start_time, tool_end_time, timing.tool_name, tool_args)

        self.tool_timings[tool_call.toolCallId] = nil
      end
    end
  end

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
  log:error("[ACP::Handler] Error: %s", error)
  self.chat:done(self.output)
end

return ACPHandler
