--[[
==========================================================
    File:       codecompanion/acp.lua
    Author:     Oli Morris
----------------------------------------------------------
    Description:
      This module implements ACP communication in CodeCompanion.
      It provides a fluent API for interacting with ACP agents,
      handling session management, and processing responses.

      Inspired by Zed's ACP implementation patterns.
==========================================================
--]]

local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local METHODS = {
  INITIALIZE = "initialize",
  AUTHENTICATE = "authenticate",
  SESSION_CANCEL = "session/cancel",
  SESSION_LOAD = "session/load",
  SESSION_NEW = "session/new",
  SESSION_PROMPT = "session/prompt",
  SESSION_REQUEST_PERMISSION = "session/request_permission",
  SESSION_UPDATE = "session/update",
  FS_READ_TEXT_FILE = "fs/read_text_file",
  FS_WRITE_TEXT_FILE = "fs/write_text_file",
}

-- TODO: Add output like chunk etc

local TIMEOUTS = {
  DEFAULT = 2e4, -- 20 seconds
  RESPONSE_POLL = 10, -- 10ms
}

local uv = vim.uv

--=============================================================================
-- ACP Connection Class - Handles the connection to ACP agents
--=============================================================================

---@class CodeCompanion.ACPConnection
---@field adapter CodeCompanion.ACPAdapter
---@field adapter_modified CodeCompanion.ACPAdapter Modified adapter with environment variables set
---@field pending_responses table<number, CodeCompanion.ACPConnection.PendingResponse>
---@field session_id string|nil
---@field _agent_info table|nil
---@field _initialized boolean
---@field _authenticated boolean
---@field _active_prompt CodeCompanion.ACPPromptBuilder|nil
---@field _state {handle: table, next_id: number, stdout_buffer: string}
---@field methods table
local Connection = {}
Connection.static = {}

---@class CodeCompanion.ACPConnection.PendingResponse
---@field result any
---@field error any

---@class CodeCompanion.ACPPromptBuilder
---@field connection CodeCompanion.ACPConnection
---@field messages table
---@field handlers table
---@field options table
---@field _sent boolean
local PromptBuilder = {}

-- Static methods for testing/mocking
Connection.static.methods = {
  decode = { default = vim.json.decode },
  encode = { default = vim.json.encode },
  job = { default = vim.system },
  schedule = { default = vim.schedule },
  schedule_wrap = { default = vim.schedule_wrap },
}

---Transform static methods for easier testing
---@param opts? table
---@return table
local function transform_static_methods(opts)
  local ret = {}
  for k, v in pairs(Connection.static.methods) do
    ret[k] = (opts and opts[k]) or v.default
  end
  return ret
end

---@class CodeCompanion.ACPConnectionArgs
---@field adapter CodeCompanion.ACPAdapter
---@field session_id? string
---@field opts? table

---Create new ACP connection
---@param args CodeCompanion.ACPConnectionArgs
---@return CodeCompanion.ACPConnection
function Connection.new(args)
  args = args or {}

  local self = setmetatable({
    adapter = args.adapter,
    adapter_modified = {},
    pending_responses = {},
    session_id = args.session_id,
    methods = transform_static_methods(args.opts),
    _initialized = false,
    _authenticated = false,
    _state = { handle = nil, next_id = 1, stdout_buffer = "" },
  }, { __index = Connection }) ---@cast self CodeCompanion.ACPConnection

  return self
end

---Check if the connection is ready
---@return boolean
function Connection:is_ready()
  return self._state.handle and self._initialized and self._authenticated and self.session_id ~= nil
end

---Connect to ACP process and establish session
---@return CodeCompanion.ACPConnection|nil self for chaining, nil on error
function Connection:connect()
  if self:is_ready() then
    return self
  end

  if not self:_spawn_process() then
    return nil
  end

  if not self._initialized then
    local initialized = self:_send_request(METHODS.INITIALIZE, self.adapter_modified.parameters)
    if not initialized then
      return log:error("[acp::connect] Failed to initialize")
    end
    self._agent_info = initialized

    -- Ensure the protocol version matches
    if
      initialized.protocolVersion and initialized.protocolVersion ~= self.adapter_modified.parameters.protocolVersion
    then
      log:warn(
        "[acp::connect] Agent selected protocolVersion=%s (client sent=%s)",
        initialized.protocolVersion,
        self.adapter_modified.parameters.protocolVersion
      )
    end

    self._initialized = true
    log:debug("[acp::connect] ACP connection initialized")
  end

  -- Authenticate only if agent supports it (authMethods not empty)
  if not self._authenticated then
    local auth_methods = (self._agent_info and self._agent_info.authMethods) or {}
    if #auth_methods > 0 then
      local wanted = self.adapter_modified.defaults.auth_method
      local methodId
      for _, m in ipairs(auth_methods) do
        if m.id == wanted then
          methodId = m.id
          break
        end
      end
      methodId = methodId or (auth_methods[1] and auth_methods[1].id)

      if methodId then
        local ok = self:_send_request(METHODS.AUTHENTICATE, { methodId = methodId })
        if not ok then
          log:error("[acp::connect] Failed to authenticate with method %s", methodId)
          return nil
        end
        log:debug("[acp::connect] Authenticated using %s", methodId)
      else
        log:debug("[acp::connect] No compatible auth method; skipping authenticate")
      end
    else
      log:debug("[acp::connect] Agent requires no authentication; skipping")
    end
    self._authenticated = true
  end

  -- Create or load session
  local can_load = self._agent_info
    and self._agent_info.agentCapabilities
    and self._agent_info.agentCapabilities.loadSession
  local session_args = {
    cwd = vim.fn.getcwd(),
    mcpServers = self.adapter_modified.defaults.mcpServers or {},
  }

  if self.session_id and can_load then
    local ok =
      self:_send_request(METHODS.SESSION_LOAD, vim.tbl_extend("force", session_args, { sessionId = self.session_id }))
    if ok ~= nil then
      log:debug("Loaded ACP session: %s", self.session_id)
    else
      log:debug("[acp::connect] session/load failed; falling back to session/new")
      can_load = false
    end
  end

  if not self.session_id or not can_load then
    local new_session = self:_send_request(METHODS.SESSION_NEW, session_args)
    if not new_session or not new_session.sessionId then
      log:error("[acp::connect] Failed to create session")
      return nil
    end
    self.session_id = new_session.sessionId
    log:debug("Created ACP session: %s", self.session_id)
  end

  return self
end

---Create the ACP process
---@return boolean success
function Connection:_spawn_process()
  local adapter = self:_setup_adapter()
  self.adapter_modified = adapter

  log:debug("Starting ACP process: %s", adapter.command)

  if adapter.handlers and adapter.handlers.setup then
    if not adapter.handlers.setup(adapter) then
      log:error("[acp::_spawn_process] Adapter setup failed")
      return false
    end
  end

  self._state.stdout_buffer = ""

  local ok, sysobj = pcall(
    self.methods.job,
    adapter.command,
    {
      stdin = true,
      cwd = vim.fn.getcwd(),
      env = adapter.env_replaced or {},
      stdout = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::_spawn_process::stdout] Error: %s", err)
        elseif data then
          self:_process_output(data)
        end
      end),
      stderr = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::_spawn_process::stderr] Error: %s", err)
        elseif data then
          for line in data:gmatch("[^\r\n]+") do
            if line ~= "" then
              log:debug("[acp::stderr] %s", line)
            end
          end
        end
      end),
    },
    self.methods.schedule_wrap(function(obj)
      self:_handle_exit(obj.code, obj.signal)
    end)
  )

  if not ok then
    log:error("[acp::_spawn_process] Failed: %s", sysobj)
    return false
  end

  self._state.handle = sysobj
  log:debug("ACP process started")
  return true
end

---Send a synchronous request and wait for response
---@param method string
---@param params table
---@return table|nil
function Connection:_send_request(method, params)
  if not self._state.handle then
    return nil
  end

  local id = self._state.next_id
  self._state.next_id = id + 1

  local request = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  if not self:_write_to_process(self.methods.encode(request) .. "\n") then
    return nil
  end

  return self:_wait_for_response(id)
end

---Send a result response to the ACP process
---@param id number
---@param result table
---@return nil
function Connection:_send_result(id, result)
  local msg = { jsonrpc = "2.0", id = id, result = result }
  self:_write_to_process(self.methods.encode(msg) .. "\n")
end

---Send an error response to the ACP process
---@param id number
---@param message string
---@param code? number
---@return nil
function Connection:_send_error(id, message, code)
  local msg = { jsonrpc = "2.0", id = id, error = { code = code or -32000, message = message } }
  self:_write_to_process(self.methods.encode(msg) .. "\n")
end

---Wait for a specific response ID
---@param id number
---@return nil
function Connection:_wait_for_response(id)
  local start_time = uv.hrtime()
  local timeout = (self.adapter_modified.defaults.timeout or TIMEOUTS.DEFAULT) * 1e6

  while uv.hrtime() - start_time < timeout do
    vim.wait(TIMEOUTS.RESPONSE_POLL)

    if self.pending_responses[id] then
      local result, err = unpack(self.pending_responses[id])
      self.pending_responses[id] = nil
      return err and nil or result
    end
  end

  log:error("[acp::_wait_for_response] Request timeout: %s", id)
  return nil
end

---Setup the adapter, making a copy and setting environment variables
---@return CodeCompanion.ACPAdapter
function Connection:_setup_adapter()
  local adapter = vim.deepcopy(self.adapter)
  adapter = adapter_utils.get_env_vars(adapter)
  adapter.parameters = adapter_utils.set_env_vars(adapter, adapter.parameters)
  adapter.defaults.auth_method = adapter_utils.set_env_vars(adapter, adapter.defaults.auth_method)
  adapter.defaults.mcpServers = adapter_utils.set_env_vars(adapter, adapter.defaults.mcpServers)
  adapter.command = adapter_utils.set_env_vars(adapter, adapter.commands.selected or adapter.commands.default)

  return adapter
end

---Disconnect and clean up the ACP process
---@return nil
function Connection:disconnect()
  log:debug("[acp::disconnect] Disconnecting ACP connection: %s", self.session_id or "[No session ID]")
  assert(self._state.handle):kill(9)
end

---Process the output - JSON-RPC doesn't guarantee message boundaries align
---with I/O boundaries, so we need to buffer and handle this carefully.
---@param data string
function Connection:_process_output(data)
  if not data or data == "" then
    return
  end

  log:debug("Received stdout:\n%s", data)
  self._state.stdout_buffer = self._state.stdout_buffer .. data

  -- Extract complete lines
  while true do
    local newline_pos = self._state.stdout_buffer:find("\n")
    if not newline_pos then
      break
    end

    local line = vim.trim(self._state.stdout_buffer:sub(1, newline_pos - 1))
    self._state.stdout_buffer = self._state.stdout_buffer:sub(newline_pos + 1)

    if line ~= "" then
      self:_process_json_message(line)
    end
  end
end

---Handle incoming JSON message
---@param line string
function Connection:_process_json_message(line)
  if not line or line == "" then
    return
  end

  -- If it doesn't look like JSON-RPC, then silently log it
  if not line:match("^%s*{") then
    log:debug("[acp::_process_json_message] Non-JSON output from agent: %s", line)
    return
  end

  local ok, message = pcall(self.methods.decode, line)
  if not ok then
    return log:error("[acp::_process_json_message] Invalid JSON:\n%s", line)
  end

  if message.id and not message.method then
    self:_store_response(message)
    if message.result and message.result ~= vim.NIL and message.result.stopReason then
      self._active_prompt:_handle_done(message.result.stopReason)
    end
  elseif message.method then
    self:_process_notification(message)
  else
    log:error("[acp::_process_json_message] Invalid message format: %s", message)
  end

  if message.error then
    log:error("[acp::_process_json_message] Error: %s", message.error)
  end
end

---Handle response to our request
---@param response table
function Connection:_store_response(response)
  if response.error then
    self.pending_responses[response.id] = { nil, response.error }
    return
  end
  self.pending_responses[response.id] = { response.result, nil }
end

---Handle notifications from the ACP process
---@param notification? table
function Connection:_process_notification(notification)
  if type(notification) ~= "table" or type(notification.method) ~= "string" then
    return log:debug("[acp::_process_notification] Malformed notification")
  end

  local sid = notification.params and notification.params.sessionId
  if sid and self.session_id and sid ~= self.session_id then
    return log:debug("[acp::_process_notification] Ignoring update for session %s (current: %s)", sid, self.session_id)
  end

  if not notification then
    log:debug("[acp::_process_notification] No notification provided")
    return self._active_prompt:_handle_done()
  end

  if notification.method == METHODS.SESSION_UPDATE then
    if self._active_prompt then
      self._active_prompt:_handle_session_update(notification.params.update)
    end
  elseif notification.method == METHODS.SESSION_REQUEST_PERMISSION then
    -- FORWARDED: handled by PromptBuilder/ACPHandler
    if self._active_prompt then
      self._active_prompt:_handle_permission_request(notification.id, notification.params)
    else
      log:debug("[acp::_process_notification] Permission request with no active prompt; ignoring")
    end
  elseif notification.method == METHODS.FS_READ_TEXT_FILE then
    self:_handle_read_file_request(notification.id, notification.params)
  elseif notification.method == METHODS.FS_WRITE_TEXT_FILE then
    self:_handle_write_file_request(notification.id, notification.params)
  else
    log:debug("[acp::_process_notification] Unhandled notification method: %s", notification.method)
  end
end

---Send data to the ACP process
---@param data string
---@return boolean
function Connection:_write_to_process(data)
  if not self._state.handle then
    log:error("[acp::_write_to_process] Process not running")
    return false
  end

  local ok, err = pcall(function()
    log:debug("[acp::_write_to_process] Sending data: %s", data)
    self._state.handle:write(data)
  end)

  if not ok then
    log:error("[acp::_write_to_process] Failed to send data: %s", err)
    return false
  end

  return true
end

---Handle fs/read_text_file requests
---@param id number
---@param params { path: string, sessionId?: string }
---@return nil
function Connection:_handle_read_file_request(id, params)
  if not id or type(params) ~= "table" then
    return
  end
  if params.sessionId and self.session_id and params.sessionId ~= self.session_id then
    return self:_send_error(id, "invalid sessionId for fs/read_text_file", -32602)
  end
  local path = params.path
  if type(path) ~= "string" then
    return self:_send_error(id, "invalid params", -32602)
  end
  local ok, content_or_err = pcall(function()
    local fd = assert(uv.fs_open(path, "r", 420))
    local stat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, stat.size, 0)) or ""
    assert(uv.fs_close(fd))
    return data
  end)
  if ok then
    self:_send_result(id, { content = content_or_err })
  else
    self:_send_error(id, ("fs/read_text_file failed: %s"):format(content_or_err))
  end
end

---Handle fs/write_text_file requests
---We carry this out here as they could arrive outside of the standard prompt flow
---@param id number
---@param params { path: string, content: string, sessionId?: string }
function Connection:_handle_write_file_request(id, params)
  if not id or type(params) ~= "table" then
    return
  end

  -- To be safe, we verify the session
  if params.sessionId and self.session_id and params.sessionId ~= self.session_id then
    return self:_send_error(id, "invalid sessionId for fs/write_text_file", -32602)
  end

  local path = params.path
  local content = params.content or ""
  if type(path) ~= "string" or type(content) ~= "string" then
    return self:_send_error(id, "invalid params", -32602)
  end

  local fs_api = require("codecompanion.strategies.chat.acp.fs")
  local ok, err = fs_api.write_text_file(path, content)
  if ok then
    -- Spec: WriteTextFileResponse is null
    self:_send_result(id, vim.NIL)
  else
    self:_send_error(id, ("fs/write_text_file failed: %s"):format(err or "unknown"))
  end
end

---Handle process exit
---@param code number
---@param signal number
function Connection:_handle_exit(code, signal)
  log:debug("[acp::_handle_exit] Process exited: code=%d, signal=%d", code, signal or 0)

  if self.adapter_modified and self.adapter_modified.handlers and self.adapter_modified.handlers.on_exit then
    self.adapter_modified.handlers.on_exit(self.adapter, code)
  end

  -- Always clean up state
  self.adapter_modified = nil
  self._initialized = false
  self._authenticated = false
  self.session_id = nil
  self.pending_responses = {}
end

---Initiate a prompt
---@param messages table
---@return CodeCompanion.ACPPromptBuilder
function Connection:prompt(messages)
  if not self.session_id then
    return log:error("[acp::prompt] Connection not established. Call connect() first.")
  end
  return PromptBuilder.new(self, messages)
end

--=============================================================================
-- PromptBuilder - Fluidly build the prompt which is sent to the agent
--=============================================================================

---Create new prompt builder
---@param connection CodeCompanion.ACPConnection
---@param messages table
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder.new(connection, messages)
  local self = setmetatable({
    connection = connection,
    handlers = {},
    messages = connection.adapter.handlers.form_messages(connection.adapter, messages),
    options = {},
    _sent = false,
  }, { __index = PromptBuilder }) ---@cast self CodeCompanion.ACPPromptBuilder

  return self
end

---Set handler for agent message chunks
---@param handler fun(content: string)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_message_chunk(handler)
  self.handlers.message_chunk = handler
  return self
end

---Set handler for agent thought chunks
---@param handler fun(content: string)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_thought_chunk(handler)
  self.handlers.thought_chunk = handler
  return self
end

---Set handler for permission requests
---@param handler fun(tool_call: table)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_permission_request(handler)
  self.handlers.permission_request = handler
  return self
end

---Set handler for tool calls
---@param handler fun(tool_call: table)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_tool_call(handler)
  self.handlers.tool_call = handler
  return self
end

---Set handler for tool call updates
---@param handler fun(tool_update: table)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_tool_update(handler)
  self.handlers.tool_update = handler
  return self
end

---Set handler for file writes
---@param handler fun(info: { path: string, bytes: number, sessionId?: string })
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_write_text_file(handler)
  self.handlers.write_text_file = handler
  return self
end

---Set handler for completion
---@param handler fun(stop_reason: string)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_complete(handler)
  self.handlers.complete = handler
  return self
end

---Set handler for errors
---@param handler fun(error: string)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_error(handler)
  self.handlers.error = handler
  return self
end

---Set request options
---@param opts table
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:with_options(opts)
  self.options = vim.tbl_extend("force", self.options, opts or {})
  return self
end

---Send the prompt
---@return table job-like object for compatibility
function PromptBuilder:send()
  if self._sent then
    error("Prompt already sent")
  end
  self._sent = true

  -- Store active prompt on connection for notifications
  self.connection._active_prompt = self

  -- Set up request options for events
  if not vim.tbl_isempty(self.options) then
    self.options.id = math.random(10000000)
    self.options.adapter = {
      name = self.connection.adapter.name,
      formatted_name = self.connection.adapter.formatted_name,
      type = self.connection.adapter.type,
      model = nil,
    }

    -- Fire request started
    if not self.options.silent then
      util.fire("RequestStarted", self.options)
    end
  end

  -- Send the prompt
  local prompt_req = {
    jsonrpc = "2.0",
    id = self.connection._state.next_id,
    method = METHODS.SESSION_PROMPT,
    params = {
      sessionId = self.connection.session_id,
      prompt = self.messages,
    },
  }

  self.connection._state.next_id = self.connection._state.next_id + 1
  local json_str = self.connection.methods.encode(prompt_req) .. "\n"

  self.connection:_write_to_process(json_str)
  self._streaming_started = false

  return {
    shutdown = function()
      self:cancel()
    end,
  }
end

---Extract renderable text from a ContentBlock (defensive)
---@param block table|nil
---@return string|nil
function PromptBuilder:_extract_text(block)
  if not block or type(block) ~= "table" then
    return nil
  end
  if block.type == "text" and type(block.text) == "string" then
    return block.text
  end
  if block.type == "resource_link" and type(block.uri) == "string" then
    return string.format("[resource: %s]", block.uri)
  end
  if block.type == "resource" and block.resource then
    local r = block.resource
    if type(r.text) == "string" then
      return r.text
    end
    if type(r.uri) == "string" then
      return string.format("[resource: %s]", r.uri)
    end
  end
  if block.type == "image" then
    return "[image]"
  end
  if block.type == "audio" then
    return "[audio]"
  end
  return nil
end

---Handle session update from the server
---@param params table
function PromptBuilder:_handle_session_update(params)
  -- Fire streaming event on first chunk
  if self.options and not self._streaming_started then
    self._streaming_started = true
    if not self.options.silent then
      util.fire("RequestStreaming", self.options)
    end
  end

  if params.sessionUpdate == "agent_message_chunk" then
    if self.handlers.message_chunk then
      local text = self:_extract_text(params.content)
      if text and text ~= "" then
        self.handlers.message_chunk(text)
      end
    end
  elseif params.sessionUpdate == "agent_thought_chunk" then
    local text = self:_extract_text(params.content)
    if text and text ~= "" then
      self.handlers.thought_chunk(text)
    end
  elseif params.sessionUpdate == "tool_call" then
    log:trace("Tool call started: %s", params.toolCallId)
    if self.handlers.tool_call then
      self.handlers.tool_call(params)
    end
  elseif params.sessionUpdate == "tool_call_update" then
    log:trace("Tool call updated: %s (status: %s)", params.toolCallId, params.status)
    if self.handlers.tool_update then
      self.handlers.tool_update(params)
    end
  end
end

---Handle permission request from the agent
---@param id string
---@param params table
---@return nil
function PromptBuilder:_handle_permission_request(id, params)
  if not id or not params then
    return
  end

  local tool_call = params.toolCall
  local options = params.options or {}

  ---Send the user's response back
  ---@param outcome table
  ---@return nil
  local function send_permission_response(outcome)
    local response_msg = {
      jsonrpc = "2.0",
      id = id,
      result = { outcome = outcome },
    }
    self.connection:_write_to_process(self.connection.methods.encode(response_msg) .. "\n")
  end

  local request = {
    id = id,
    session_id = params.sessionId,
    tool_call = tool_call,
    options = options,
    respond = function(option_id, canceled)
      if canceled or not option_id then
        send_permission_response({ outcome = "canceled" })
      else
        send_permission_response({ outcome = "selected", optionId = option_id })
      end
    end,
  }

  if self.handlers.permission_request then
    self.handlers.permission_request(request)
  else
    -- Safe default to avoid hanging agent
    request.respond(nil, true)
  end
end

---Handle done event from the server
---@param stop_reason? string
---@return nil
function PromptBuilder:_handle_done(stop_reason)
  if self.handlers.complete then
    self.handlers.complete(stop_reason)
  end

  -- Fire request finished event
  if self.options and not self.options.silent then
    self.options.status = "success"
    util.fire("RequestFinished", self.options)
  end

  -- Clear active prompt
  self.connection._active_prompt = nil
end

---Cancel the prompt
function PromptBuilder:cancel()
  if self.connection.session_id then
    local cancel_req = {
      jsonrpc = "2.0",
      method = METHODS.SESSION_CANCEL,
      params = { sessionId = self.connection.session_id },
    }

    self.connection._state.next_id = self.connection._state.next_id + 1
    local json_str = self.connection.methods.encode(cancel_req) .. "\n"
    self.connection:_write_to_process(json_str)

    if self.options and not self.options.silent then
      self.options.status = "cancelled" -- Keep this as UK spelling
      util.fire("RequestFinished", self.options)
    end
  end

  self.connection._active_prompt = nil
end

return Connection
