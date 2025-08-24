--[[
==========================================================
    File:       codecompanion/acp/init.lua
    Author:     Oli Morris
----------------------------------------------------------
    Description:
      This module implements ACP communication in CodeCompanion.
      It provides a fluent API for interacting with ACP agents,
      handling session management, and processing responses.

      Inspired by Zed's ACP implementation patterns.
==========================================================
--]]

local METHODS = require("codecompanion.acp.methods")
local PromptBuilder = require("codecompanion.acp.prompt_builder")
local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")

local TIMEOUTS = {
  DEFAULT = 2e4, -- 20 seconds
  RESPONSE_POLL = 10, -- 10ms
}

local uv = vim.uv

--=============================================================================
-- ACP Connection Class - Handles the connection to ACP agents
--=============================================================================

---@class CodeCompanion.ACP.Connection
---@field adapter CodeCompanion.ACPAdapter
---@field adapter_modified CodeCompanion.ACPAdapter Modified adapter with environment variables set
---@field pending_responses table<number, CodeCompanion.ACP.Connection.PendingResponse>
---@field session_id string|nil
---@field _agent_info table|nil
---@field _initialized boolean
---@field _authenticated boolean
---@field _active_prompt CodeCompanion.ACP.PromptBuilder|nil
---@field _state {handle: table, next_id: number, stdout_buffer: string}
---@field methods table
local Connection = {}
Connection.static = {}

Connection.METHODS = METHODS

---@class CodeCompanion.ACP.Connection.PendingResponse
---@field result any
---@field error any

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
---@return CodeCompanion.ACP.Connection
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
  }, { __index = Connection }) ---@cast self CodeCompanion.ACP.Connection

  return self
end

---Check if the connection is ready
---@return boolean
function Connection:is_ready()
  return self._state.handle and self._initialized and self._authenticated and self.session_id ~= nil
end

---Connect to ACP process and establish session
---@return CodeCompanion.ACP.Connection|nil self for chaining, nil on error
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

    local line = self._state.stdout_buffer:sub(1, newline_pos - 1):gsub("\r$", "")
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
      if self._active_prompt and self._active_prompt._handle_done then
        self._active_prompt:_handle_done(message.result.stopReason)
      end
    end
  elseif message.method then
    self:_process_incoming(message)
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

---Send a notification to the ACP process
---@param method string
---@param params table
---@return nil
function Connection:_notify(method, params)
  local msg = { jsonrpc = "2.0", method = method, params = params or {} }
  self:_write_to_process(self.methods.encode(msg) .. "\n")
end

---Handle incoming requests and notifications from the ACP agent process
---@param notification? table
function Connection:_process_incoming(notification)
  if type(notification) ~= "table" or type(notification.method) ~= "string" then
    return log:debug("[acp::_process_incoming] Malformed notification")
  end

  local sid = notification.params and notification.params.sessionId
  local is_request = notification.id ~= nil
  if sid and self.session_id and sid ~= self.session_id then
    if is_request then
      return self:_send_error(notification.id, "invalid sessionId", -32602)
    end
    return log:debug("[acp::_process_incoming] Ignoring update for session %s (current: %s)", sid, self.session_id)
  end

  local DISPATCH = self._dispatch
    or {
      [self.METHODS.SESSION_UPDATE] = function(s, m)
        if s._active_prompt then
          s._active_prompt:_handle_session_update(m.params.update)
        end
      end,
      [self.METHODS.SESSION_REQUEST_PERMISSION] = function(s, m)
        if s._active_prompt then
          s._active_prompt:_handle_permission_request(m.id, m.params)
        else
          log:debug("[acp::_process_incoming] Permission request with no active prompt; ignoring")
        end
      end,
      [self.METHODS.FS_READ_TEXT_FILE] = function(s, m)
        s:_handle_read_file_request(m.id, m.params)
      end,
      [self.METHODS.FS_WRITE_TEXT_FILE] = function(s, m)
        s:_handle_write_file_request(m.id, m.params)
      end,
    }
  self._dispatch = DISPATCH

  local handler = DISPATCH[notification.method]
  if handler then
    return handler(self, notification)
  end
  log:debug("[acp::_process_incoming] Unhandled notification method: %s", notification.method)
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
    local info = { path = path, bytes = #content, sessionId = params.sessionId }
    if self._active_prompt and self._active_prompt.handlers and self._active_prompt.handlers.write_text_file then
      pcall(self._active_prompt.handlers.write_text_file, info)
    end
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
    self.adapter_modified.handlers.on_exit(self.adapter_modified, code)
  end

  -- Always clean up state
  self.adapter_modified = nil
  self._initialized = false
  self._authenticated = false
  self.session_id = nil
  self.pending_responses = {}

  if self._active_prompt and self._active_prompt._handle_done then
    pcall(function()
      self._active_prompt:_handle_done("canceled")
    end)
  end
  self._active_prompt = nil
end

---Initiate a prompt
---@param messages table
---@return CodeCompanion.ACP.PromptBuilder
function Connection:prompt(messages)
  if not self.session_id then
    return log:error("[acp::prompt] Connection not established. Call connect() first.")
  end
  return PromptBuilder.new(self, messages)
end

return Connection
