--[[
===============================================================================
    File:       codecompanion/acp/init.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      This module implements ACP communication in CodeCompanion.
      It provides a fluent API for interacting with ACP agents,
      handling session management, and processing responses.

      Inspired by Zed's ACP implementation patterns.

      This code is licensed under the MIT License.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
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
---@field _agent_info {agentCapabilities: ACP.agentCapabilities, authMethods: ACP.authMethods, protocolVersion: number}|nil
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
function Connection:is_connected()
  return self._state.handle and self._initialized and self._authenticated and self.session_id ~= nil
end

---Connect and initialize the ACP process and establish session
---@return CodeCompanion.ACP.Connection|nil self for chaining, nil on error
function Connection:connect_and_initialize()
  if self:is_connected() then
    return self
  end

  if not self:start_agent_process() then
    return nil
  end

  if not self._initialized then
    local initialized = self:send_rpc_request(METHODS.INITIALIZE, self.adapter_modified.parameters)
    if not initialized then
      return log:error("[acp::connect_and_initialize] Failed to initialize")
    end
    self._agent_info = initialized

    -- Ensure the protocol version matches
    if
      initialized.protocolVersion and initialized.protocolVersion ~= self.adapter_modified.parameters.protocolVersion
    then
      log:warn(
        "[acp::connect_and_initialize] Agent selected protocolVersion=%s (client sent=%s)",
        initialized.protocolVersion,
        self.adapter_modified.parameters.protocolVersion
      )
    end

    self._initialized = true
    log:debug("[acp::connect_and_initialize] ACP connection initialized")
  end

  -- Allow adapters to handle authentication themselves
  if
    not self._authenticated
    and self.adapter_modified
    and self.adapter_modified.handlers
    and self.adapter_modified.handlers.auth
  then
    local ok, adapter_authenticated = pcall(self.adapter_modified.handlers.auth, self.adapter_modified)
    if not ok then
      log:error("[acp::connect_and_initialize] Adapter auth hook failed: %s", adapter_authenticated)
      return nil
    end
    if adapter_authenticated == true then
      self._authenticated = true
      log:debug("[acp::connect_and_initialize] Authentication handled by adapter; skipping RPC authenticate")
    end
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
        local ok = self:send_rpc_request(METHODS.AUTHENTICATE, { methodId = methodId })
        if not ok then
          log:error("[acp::connect_and_initialize] Failed to authenticate with method %s", methodId)
          return nil
        end
        log:debug("[acp::connect_and_initialize] Authenticated using %s", methodId)
      else
        log:debug("[acp::connect_and_initialize] No compatible auth method; skipping authenticate")
      end
    else
      log:debug("[acp::connect_and_initialize] Agent requires no authentication; skipping")
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
    local ok = self:send_rpc_request(
      METHODS.SESSION_LOAD,
      vim.tbl_extend("force", session_args, { sessionId = self.session_id })
    )
    if ok ~= nil then
      log:debug("[acp::connect_and_initialize]: Loaded session %s", self.session_id)
    else
      log:debug("[acp::connect_and_initialize] session/load failed; falling back to session/new")
      can_load = false
    end
  end

  if not self.session_id or not can_load then
    local new_session = self:send_rpc_request(METHODS.SESSION_NEW, session_args)
    if not new_session or not new_session.sessionId then
      log:error("[acp::connect_and_initialize] Failed to create session")
      return nil
    end
    self.session_id = new_session.sessionId
    log:debug("Created ACP session: %s", self.session_id)
  end

  return self
end

---Create the ACP process
---@return boolean success
function Connection:start_agent_process()
  local adapter = self:prepare_adapter()
  self.adapter_modified = adapter

  log:debug("Starting ACP process: %s", adapter.command)

  if adapter.handlers and adapter.handlers.setup then
    if not adapter.handlers.setup(adapter) then
      log:error("[acp::start_agent_process] Adapter setup failed")
      return false
    end
  end

  self._state.stdout_buffer = ""

  local ok, sysobj = pcall(
    self.methods.job,
    self.adapter_modified.command,
    {
      stdin = true,
      cwd = vim.fn.getcwd(),
      env = adapter.env_replaced or {},
      stdout = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::start_agent_process::stdout] Error: %s", err)
        elseif data then
          self:buffer_stdout_and_dispatch(data)
        end
      end),
      stderr = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::start_agent_process::stderr] Error: %s", err)
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
      self:handle_process_exit(obj.code, obj.signal)
    end)
  )

  if not ok then
    log:error("[acp::start_agent_process] Failed: %s", sysobj)
    return false
  end

  self._state.handle = sysobj
  log:debug("[acp::start_agent_process] ACP process started")
  return true
end

---Send a synchronous request and wait for response
---@param method string
---@param params table
---@return table|nil
function Connection:send_rpc_request(method, params)
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

  if not self:write_message(self.methods.encode(request) .. "\n") then
    return nil
  end

  return self:wait_for_rpc_response(id)
end

---Send a result response to the ACP process
---@param id number
---@param result table
---@return nil
function Connection:send_result(id, result)
  local msg = { jsonrpc = "2.0", id = id, result = result }
  self:write_message(self.methods.encode(msg) .. "\n")
end

---Send an error response to the ACP process
---@param id number
---@param message string
---@param code? number
---@return nil
function Connection:send_error(id, message, code)
  code = code or -32000
  local msg = { jsonrpc = "2.0", id = id, error = { code = code, message = message } }
  self:write_message(self.methods.encode(msg) .. "\n")
end

---Wait for a specific response ID
---@param id number
---@return nil
function Connection:wait_for_rpc_response(id)
  local start_time = uv.hrtime()
  local timeout = (self.adapter_modified.defaults.timeout or TIMEOUTS.DEFAULT) * 1e6 -- Nanoseconds to milliseconds

  while uv.hrtime() - start_time < timeout do
    vim.wait(TIMEOUTS.RESPONSE_POLL)

    if self.pending_responses[id] then
      local result, err = unpack(self.pending_responses[id])
      self.pending_responses[id] = nil
      return err and nil or result
    end
  end

  log:error("[acp::wait_for_rpc_response] Request timeout ID %s", id)
  return nil
end

---Setup the adapter, making a copy and setting environment variables
---@return CodeCompanion.ACPAdapter
function Connection:prepare_adapter()
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
function Connection:buffer_stdout_and_dispatch(data)
  if not data or data == "" then
    return
  end

  log:debug("[acp::buffer_stdout_and_dispatch] Received stdout:\n%s", data)
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
      self:handle_rpc_message(line)
    end
  end
end

---Handle incoming JSON message
---@param line string
function Connection:handle_rpc_message(line)
  if not line or line == "" then
    return
  end

  -- If it doesn't look like JSON-RPC, then silently log it
  if not line:match("^%s*{") then
    log:debug("[acp::handle_rpc_message] Non-JSON output from agent: %s", line)
    return
  end

  local ok, message = pcall(self.methods.decode, line)
  if not ok then
    return log:error("[acp::handle_rpc_message] Invalid JSON:\n%s", line)
  end

  if message.id and not message.method then
    self:store_rpc_response(message)
    if message.result and message.result ~= vim.NIL and message.result.stopReason then
      if self._active_prompt and self._active_prompt.handle_done then
        self._active_prompt:handle_done(message.result.stopReason)
      end
    end
  elseif message.method then
    self:handle_incoming_request_or_notification(message)
  else
    log:error("[acp::handle_rpc_message] Invalid message format: %s", message)
  end

  if message.error then
    log:error("[acp::handle_rpc_message] Error: %s", message.error)
  end
end

---Handle response to our request
---@param response table
function Connection:store_rpc_response(response)
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
function Connection:send_notification(method, params)
  local msg = { jsonrpc = "2.0", method = method, params = params or {} }
  self:write_message(self.methods.encode(msg) .. "\n")
end

---Handle incoming requests and notifications from the ACP agent process
---@param notification? table
function Connection:handle_incoming_request_or_notification(notification)
  if type(notification) ~= "table" or type(notification.method) ~= "string" then
    return log:debug("[acp::handle_incoming_request_or_notification] Malformed notification")
  end

  local sid = notification.params and notification.params.sessionId
  local is_request = notification.id ~= nil
  if sid and self.session_id and sid ~= self.session_id then
    if is_request then
      return self:send_error(notification.id, "invalid sessionId", -32602)
    end
    return log:debug(
      "[acp::handle_incoming_request_or_notification] Ignoring update for session %s (current: %s)",
      sid,
      self.session_id
    )
  end

  local DISPATCH = self._dispatch
    or {
      [self.METHODS.SESSION_UPDATE] = function(s, m)
        if s._active_prompt then
          s._active_prompt:handle_session_update(m.params.update)
        end
      end,
      [self.METHODS.SESSION_REQUEST_PERMISSION] = function(s, m)
        if s._active_prompt then
          s._active_prompt:handle_permission_request(m.id, m.params)
        else
          log:debug("[acp::handle_incoming_request_or_notification] Permission request with no active prompt; ignoring")
        end
      end,
      [self.METHODS.FS_READ_TEXT_FILE] = function(s, m)
        s:handle_fs_read_text_file_request(m.id, m.params)
      end,
      [self.METHODS.FS_WRITE_TEXT_FILE] = function(s, m)
        s:handle_fs_write_file_request(m.id, m.params)
      end,
    }
  self._dispatch = DISPATCH

  local handler = DISPATCH[notification.method]
  if handler then
    return handler(self, notification)
  end
  log:debug("[acp::handle_incoming_request_or_notification] Unhandled notification method: %s", notification.method)
end

---Send data to the ACP process
---@param data string
---@return boolean
function Connection:write_message(data)
  if not self._state.handle then
    log:error("[acp::write_message] Process not running")
    return false
  end

  local ok, err = pcall(function()
    log:debug("[acp::write_message] Sending data:\n%s", data)
    self._state.handle:write(data)
  end)

  if not ok then
    log:error("[acp::write_message] Failed to send data: %s", err)
    return false
  end

  return true
end

---Handle fs/read_text_file requests
---@param id number
---@param params { path: string, sessionId?: string, limit?: number|nil, line?: number|nil }
---@return nil
function Connection:handle_fs_read_text_file_request(id, params)
  if not id or type(params) ~= "table" then
    return
  end

  if params.sessionId and self.session_id and params.sessionId ~= self.session_id then
    return self:send_error(id, "invalid sessionId for fs/read_text_file", -32602)
  end

  local path = params.path
  if type(path) ~= "string" then
    return self:send_error(id, "invalid params", -32602)
  end

  local fs = require("codecompanion.strategies.chat.acp.fs")
  local ok, content = fs.read_text_file(path, { line = params.line, limit = params.limit })
  if ok then
    return self:send_result(id, { content = content })
  end

  -- If the file does not exist we treat it as empty so the agent can create it
  local errstr = tostring(content)
  if errstr:find("ENOENT", 1, true) then
    self:send_result(id, { content = "" })
    return
  end

  -- Other errors: send as JSON-RPC error
  self:send_error(id, ("fs/read_text_file failed: %s"):format(errstr))
end

---Handle fs/write_text_file requests
---We carry this out here as they could arrive outside of the standard prompt flow
---@param id number
---@param params { path: string, content: string, sessionId?: string }
function Connection:handle_fs_write_file_request(id, params)
  if not id or type(params) ~= "table" then
    return
  end

  if params.sessionId and self.session_id and params.sessionId ~= self.session_id then
    return self:send_error(id, "invalid sessionId for fs/write_text_file", -32602)
  end

  local path = params.path
  local content = params.content or ""
  if type(path) ~= "string" or type(content) ~= "string" then
    return self:send_error(id, "invalid params", -32602)
  end

  local fs = require("codecompanion.strategies.chat.acp.fs")
  local ok, err = fs.write_text_file(path, content)
  if ok then
    -- Spec: WriteTextFileResponse is null
    self:send_result(id, vim.NIL)
    local info = { path = path, bytes = #content, sessionId = params.sessionId }
    if self._active_prompt and self._active_prompt.handlers and self._active_prompt.handlers.write_text_file then
      pcall(self._active_prompt.handlers.write_text_file, info)
    end
  else
    self:send_error(id, ("fs/write_text_file failed: %s"):format(err or "unknown"))
  end
end

---Handle process exit
---@param code number
---@param signal number
function Connection:handle_process_exit(code, signal)
  log:debug("[acp::handle_process_exit] Process exited: code=%d, signal=%d", code, signal or 0)

  if self.adapter_modified and self.adapter_modified.handlers and self.adapter_modified.handlers.on_exit then
    self.adapter_modified.handlers.on_exit(self.adapter_modified, code)
  end

  -- Always clean up state
  self.adapter_modified = nil
  self._initialized = false
  self._authenticated = false
  self.session_id = nil
  self.pending_responses = {}

  if self._active_prompt and self._active_prompt.handle_done then
    pcall(function()
      self._active_prompt:handle_done("canceled")
    end)
  end
  self._active_prompt = nil
end

---Initiate a prompt
---@param messages table
---@return CodeCompanion.ACP.PromptBuilder
function Connection:session_prompt(messages)
  if not self.session_id then
    return log:error("[acp::session_prompt] Connection not established. Call connect_and_initialize() first.")
  end
  return PromptBuilder.new(self, messages)
end

return Connection
