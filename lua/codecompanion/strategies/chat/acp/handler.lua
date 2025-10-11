local config = require("codecompanion.config")
local formatter = require("codecompanion.strategies.chat.acp.formatters")
local log = require("codecompanion.utils.log")

---@type number Maximum length for tool titles in super_diff
local MAX_TOOL_TITLE_LENGTH = 60

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table<string, table> Cache of tool calls by their ID
---@field tool_edit_map table<string, string> Map of toolCallId to edit_tracker edit_id
local ACPHandler = {}

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Chat.ACPHandler
function ACPHandler.new(chat)
  local self = setmetatable({
    chat = chat,
    output = {},
    reasoning = {},
    tools = {},
    tool_edit_map = {},
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

---Sanitize tool title to prevent showing invalid or malformed content
---@param title string|nil The raw title from tool_call
---@param tool_call_id string The toolCallId as fallback
---@return string sanitized_title A clean, readable title
local function sanitize_tool_title(title, tool_call_id)
  if not title or title == "" then
    return "ACP:" .. tool_call_id
  end

  -- If title contains newlines, the agent is sending malformed data - use just toolCallId
  if title:find("\n") or title:find("\r") then
    return "ACP:" .. tool_call_id
  end

  -- Truncate long titles and append to toolCallId format
  if #title > MAX_TOOL_TITLE_LENGTH then
    return "ACP:" .. tool_call_id .. " (" .. title:sub(1, MAX_TOOL_TITLE_LENGTH) .. "...)"
  end

  return "ACP:" .. tool_call_id .. " (" .. title .. ")"
end

---Track tool edit operations for super_diff
---@param tool_call table The tool call/update from ACP
---@return string|nil edit_id The registered edit ID if tracked
function ACPHandler:track_tool_edit(tool_call)
  local kind = tool_call.kind
  if not kind and tool_call.toolCallId and self.tools[tool_call.toolCallId] then
    kind = self.tools[tool_call.toolCallId].kind
  end

  if kind ~= "edit" or not tool_call.content then
    log:trace("[ACPHandler] Skipping non-edit tool call: kind=%s, has_content=%s", kind, tool_call.content ~= nil)
    return nil
  end

  local content = tool_call.content[1]
  if not content or content.type ~= "diff" then
    return nil
  end

  -- WARNING: this logic because of inconsistent tool_call path data from gemini_cli
  -- Get filepath - priority: current locations > cached locations > content path
  local filepath = nil

  -- Try current tool_call locations first (most reliable, usually absolute)
  if tool_call.locations and tool_call.locations[1] and tool_call.locations[1].path then
    filepath = tool_call.locations[1].path
  end

  -- If not found, check cached tool call for locations
  if not filepath and tool_call.toolCallId and self.tools[tool_call.toolCallId] then
    local cached = self.tools[tool_call.toolCallId]
    if cached.locations and cached.locations[1] and cached.locations[1].path then
      filepath = cached.locations[1].path
    end
  end

  -- Fall back to content path (often relative in gemini_cli)
  if not filepath then
    filepath = content.path
  end

  if not filepath then
    log:debug("[ACPHandler] No filepath found in tool call: %s", tool_call.toolCallId)
    return nil
  end

  -- This is a defensive mechanism: normalize path for gemini_cli
  filepath = vim.fs.normalize(filepath)

  -- Prevent circular dependencies and enable more efficient lazy-loading
  local edit_tracker = require("codecompanion.strategies.chat.edit_tracker")

  -- Register edit if not already tracked
  if not self.tool_edit_map[tool_call.toolCallId] then
    edit_tracker.init(self.chat)

    local initial_status = "pending"
    if tool_call.status == "completed" then
      initial_status = "accepted"
    elseif tool_call.status == "failed" or tool_call.status == "cancelled" then
      initial_status = "rejected"
    end

    local edit_id = edit_tracker.register_edit_operation(self.chat, {
      filepath = filepath,
      tool_name = sanitize_tool_title(tool_call.title, tool_call.toolCallId),
      original_content = vim.split(content.oldText or "", "\n", { plain = true }),
      new_content = vim.split(content.newText or "", "\n", { plain = true }),
      status = initial_status,
      metadata = {
        explanation = tool_call.title,
        tool_call_id = tool_call.toolCallId,
        kind = tool_call.kind,
        auto_detected = false,
        detection_method = "acp_tool_call",
      },
    })

    if edit_id and tool_call.toolCallId then
      self.tool_edit_map[tool_call.toolCallId] = edit_id
      log:debug("[ACPHandler] Tracked edit for %s (edit_id=%s, status=%s)", filepath, edit_id, initial_status)
    else
      log:debug("[ACPHandler] Failed to register edit: edit_id=%s, toolCallId=%s", edit_id, tool_call.toolCallId)
    end

    return edit_id
  elseif tool_call.status and self.tool_edit_map[tool_call.toolCallId] then
    -- Update status on tool_call_update (only if status changed)
    local edit_id = self.tool_edit_map[tool_call.toolCallId]
    local status_map = {
      completed = "accepted",
      failed = "rejected",
      cancelled = "rejected",
    }
    if status_map[tool_call.status] then
      edit_tracker.update_edit_status(self.chat, edit_id, status_map[tool_call.status])
      log:trace("[ACPHandler] Updated edit status to %s for %s", status_map[tool_call.status], filepath)
    end
  end

  return nil
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

  local ok, content = pcall(formatter.tool_message, tool_call, self.chat.adapter)
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
  -- Merge with cache first to get complete data (including locations, because of gemini_cli)
  local id = tool_call.toolCallId
  if id and self.tools[id] then
    tool_call = merge_tool_call(self.tools[id], tool_call)
  end

  self:track_tool_edit(tool_call)
  return self:process_tool_call(tool_call)
end

---Handle tool call updates and their respective status
---@param tool_call table
function ACPHandler:handle_tool_update(tool_call)
  -- Merge with cache first to get complete data (including locations, because of gemini_cli)
  local id = tool_call.toolCallId
  if id and self.tools[id] then
    tool_call = merge_tool_call(self.tools[id], tool_call)
  end

  self:track_tool_edit(tool_call)
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

  -- Cache the tool_call for edit tracking (some agents `gemini_cli` skip the initial tool_call notification)
  if tool_call and tool_call.toolCallId then
    self.tools[tool_call.toolCallId] = merge_tool_call(self.tools[tool_call.toolCallId], tool_call)
    self:track_tool_edit(tool_call)
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
