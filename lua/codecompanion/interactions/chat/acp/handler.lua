local async = require("codecompanion.utils.async")
local config = require("codecompanion.config")
local formatter = require("codecompanion.interactions.chat.acp.formatters")
local log = require("codecompanion.utils.log")
local markdown = require("codecompanion.utils.markdown")
local tool_calls = require("codecompanion.interactions.chat.ui.tool_calls")
local utils = require("codecompanion.utils")
local watch = require("codecompanion.interactions.shared.watch")

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table<string, table> Cache of tool calls by their ID
---@field edits table<string, { path: string, line?: number }[]> Files each tool call has edited, by tool call ID
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
    edits = {},
    ui_state = {},
  }, { __index = ACPHandler })

  return self --[[@type CodeCompanion.Chat.ACPHandler]]
end

---Merge an incoming tool call or update into the cached tool call
---@param opts { existing?: table, incoming?: table }
---@return table
function ACPHandler.merge_tool_call(opts)
  local merged = vim.deepcopy(opts.existing or {})
  for key, value in pairs(opts.incoming or {}) do
    if value ~= vim.NIL then
      merged[key] = value
    end
  end
  return merged
end

---The files a tool call update edits, alongside locations and diffs
---@param tool_call table
---@return { path: string, line?: number }[]
local function touched_files(tool_call)
  local touched = {}

  for _, location in ipairs(tool_call.locations or {}) do
    table.insert(touched, { path = location.path, line = location.line })
  end
  for _, content in ipairs(tool_call.content or {}) do
    if content.type == "diff" then
      table.insert(touched, { path = content.path })
    end
  end

  return touched
end

---Submit payload to ACP, registering the request on the chat before connecting
---@param payload table The payload to send to the LLM
---@return nil
function ACPHandler:submit(payload)
  local request = {}
  request.cancel = function()
    request.cancelled = true
    if request.prompt then
      request.prompt.cancel()
    end
  end

  -- IMPORTANT: Registered before the connect below, so a second <CR> can't start a parallel submit
  self.chat.current_request = request

  -- Keep the agent's request off the main loop
  async.sync(function()
    local session_ready = self:ensure_connection() and self:ensure_session()

    -- A stop or a newer submission can replace this request while the agent boots,
    -- reporting from here would clear the handle belonging to that request
    if request.cancelled or self.chat.current_request ~= request then
      return
    end

    if not session_ready then
      self.chat.status = "error"
      return self.chat:done({ output = self.output })
    end

    request.prompt = self:create_and_send_prompt(payload)
  end)()
end

---Ensure the ACP connection is authenticated
---@return boolean
function ACPHandler:ensure_connection()
  -- If the async init already created the connection, check if it's ready
  if self.chat.acp_connection and self.chat.acp_connection:is_ready() then
    return true
  end

  if not self.chat.acp_connection then
    local adapter = self.chat.adapter --[[@as CodeCompanion.ACPAdapter]]
    self.chat.acp_connection = require("codecompanion.acp").new({
      adapter = adapter,
      chat = self.chat,
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

  require("codecompanion.interactions.chat.acp.defaults").apply(self.chat.adapter, conn)

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
  local messages = self:transform_acp_commands(payload.messages)

  return self.chat.acp_connection
    :session_prompt(messages)
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
      self.chat.acp_permissions:push(request)
    end)
    :on_complete(function()
      self:handle_complete()
    end)
    :on_error(function(error)
      self:handle_error(error)
    end)
    :on_cancel(function()
      self.chat.acp_permissions:cancel_turn()
    end)
    :with_options({ bufnr = self.chat.bufnr, interaction = "chat" })
    :send()
end

---Handle incoming message chunks
---@param content string
---@return nil
function ACPHandler:handle_message_chunk(content)
  table.insert(self.output, content)
  self.chat:add_buf_message(
    { role = config.constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )
end

---Handle incoming thought chunks
---@param content string
---@return nil
function ACPHandler:handle_thought_chunk(content)
  table.insert(self.reasoning, content)
  if config.display.chat.show_reasoning then
    self.chat:add_buf_message(
      { role = config.constants.LLM_ROLE, content = content },
      { type = self.chat.MESSAGE_TYPES.REASONING_MESSAGE }
    )
  end
end

---Remember the files a tool call names, as a later update can arrive without them
---@param opts { edits: table<string, table[]>, id: string, tool_call: table }
---@return nil
function ACPHandler.track_edits(opts)
  local edits = opts.edits[opts.id] or {}

  for _, file in ipairs(touched_files(opts.tool_call)) do
    local existing = vim.iter(edits):find(function(edit)
      return edit.path == file.path
    end)

    if existing then
      existing.line = existing.line or file.line
    elseif type(file.path) == "string" and file.path ~= "" then
      table.insert(edits, file)
    end
  end

  opts.edits[opts.id] = edits
end

---Release a finished tool call's files, firing an event for each one it edited
---@param opts { edits: table<string, table[]>, id: string, tool_call: table, tool: string }
---@return nil
function ACPHandler.flush_edits(opts)
  local tool_call = opts.tool_call
  if tool_call.status ~= "completed" and tool_call.status ~= "failed" then
    return
  end

  local edits = opts.edits[opts.id]
  opts.edits[opts.id] = nil

  if tool_call.status == "failed" or tool_call.kind ~= "edit" then
    return
  end

  for _, file in ipairs(edits or {}) do
    utils.fire("FileEdited", { path = file.path, tool = opts.tool, line = file.line })
  end
end

---Update an existing tool call line such as when the status changes
---@param opts { id: string, status: string, summary: string }
---@return boolean updated
function ACPHandler:_update_tool_call_line(opts)
  local cached = self.ui_state[opts.id]
  if not cached then
    return false
  end

  local ok, update = pcall(tool_calls.update, self.chat, {
    icon_id = cached.icon_id,
    line_number = cached.line_number,
    status = opts.status,
    summary = opts.summary,
  })
  local is_updated = ok and update.is_updated

  if opts.status == "completed" then
    self.ui_state[opts.id] = nil
  elseif is_updated and update.icon_id then
    cached.icon_id = update.icon_id
  end

  if not is_updated then
    log:debug("[ACP::Handler] Failed to update tool call line for toolCallId %s", opts.id)
  end
  return is_updated
end

---Output tool call to the chat
---@param tool_call table
---@return nil
function ACPHandler:process_tool_call(tool_call)
  local id = tool_call.toolCallId

  local merged = ACPHandler.merge_tool_call({ existing = self.tools[id], incoming = tool_call })
  tool_call = merged

  ACPHandler.track_edits({ edits = self.edits, id = id, tool_call = tool_call })
  self.chat.tool_calls.acp[id] = merged

  -- Cache or cleanup
  if tool_call.status == "completed" then
    self.tools[id] = nil
  else
    self.tools[id] = merged
  end

  ACPHandler.flush_edits({ edits = self.edits, id = id, tool_call = tool_call, tool = self.chat.adapter.name })

  -- Pending tool calls are awaiting approval or streaming input, so hold them
  -- back from the buffer until the agent moves them out of the pending state
  if tool_call.status == "pending" then
    return
  end

  local ok, message = pcall(formatter.tool_message, { tool_call = tool_call, adapter = self.chat.adapter })
  local content = ok and message.summary or "[Error formatting tool output]"

  if self:_update_tool_call_line({ id = id, status = tool_call.status, summary = content }) then
    return
  end

  self.ui_state[id] = tool_calls.write(self.chat, {
    call_id = id,
    status = tool_call.status or "in_progress",
    summary = content,
  })
end

---Handle the prompt response when it's complete
---@return nil
function ACPHandler:handle_complete()
  self.chat.acp_permissions:cancel_turn()

  if not self.chat.status or self.chat.status == "" then
    self.chat.status = "success"
  end

  self.chat:done({ output = self.output, reasoning = self.reasoning, tools = {} })
end

---Handle errors
---@param error string
---@return nil
function ACPHandler:handle_error(error)
  self.chat.acp_permissions:cancel_turn()

  self.chat.status = "error"
  log:error("[ACP::Handler] %s", error)

  self.chat:add_buf_message(
    { role = config.constants.LLM_ROLE, content = "\n" .. markdown.form_codeblock(error, { ft = "txt" }) },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )

  self.chat:done({ output = self.output, error = error })
end

return ACPHandler
