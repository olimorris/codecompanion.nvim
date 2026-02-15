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

      This code is licensed under the Apache-2.0 License.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local METHODS = require("codecompanion.acp.methods")
local PromptBuilder = require("codecompanion.acp.prompt_builder")
local adapter_utils = require("codecompanion.utils.adapters")
local config = require("codecompanion.config")
local jsonrpc = require("codecompanion.utils.jsonrpc")
local log = require("codecompanion.utils.log")

local TIMEOUTS = {
  DEFAULT = 2e4, -- 20 seconds
  RESPONSE_POLL = 10, -- 10ms
}

local api = vim.api
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
---@field _state {handle: table, id_gen: CodeCompanion.JsonRPC.IdGenerator, line_buffer: CodeCompanion.JsonRPC.LineBuffer}
---@field _modes {currentModeId: string, availableModes: table[]}|nil
---@field _models {currentModelId: string, availableModels: table[]}|nil
---@field methods table
local Connection = {}

Connection.METHODS = METHODS

---@class CodeCompanion.ACP.Connection.PendingResponse
---@field result any
---@field error any

local METHOD_DEFAULTS = {
  decode = vim.json.decode,
  encode = vim.json.encode,
  job = vim.system,
  schedule = vim.schedule,
  schedule_wrap = vim.schedule_wrap,
}

---@class CodeCompanion.ACPConnectionArgs
---@field adapter CodeCompanion.ACPAdapter
---@field session_id? string
---@field opts? table

---Create new ACP connection
---@param args CodeCompanion.ACPConnectionArgs
---@return CodeCompanion.ACP.Connection
function Connection.new(args)
  args = args or {}

  local methods = vim.tbl_extend("force", METHOD_DEFAULTS, args.opts or {})

  local self = setmetatable({
    adapter = args.adapter,
    adapter_modified = {},
    pending_responses = {},
    session_id = args.session_id,
    methods = methods,
    _initialized = false,
    _authenticated = false,
    _modes = nil,
    _state = { handle = nil, id_gen = jsonrpc.IdGenerator.new(), line_buffer = jsonrpc.LineBuffer.new() },
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

    log:debug("[acp::connect_and_initialize] Agent info: %s", initialized)

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

    api.nvim_create_autocmd("VimLeavePre", {
      group = api.nvim_create_augroup("codecompanion.acp.disconnect", { clear = true }),
      callback = function()
        pcall(function()
          return self:disconnect()
        end)
      end,
    })
  end

  if not self:_authenticate() then
    return nil
  end

  if not self:_establish_session() then
    return nil
  end

  self:apply_default_model()

  return self
end

---Authenticate the connection via adapter hook or agent auth methods
---@return boolean success
function Connection:_authenticate()
  -- Allow adapters to handle authentication themselves
  if
    not self._authenticated
    and self.adapter_modified
    and self.adapter_modified.handlers
    and self.adapter_modified.handlers.auth
  then
    local ok, result = pcall(self.adapter_modified.handlers.auth, self.adapter_modified)
    if not ok then
      log:error("[acp::_authenticate] Adapter auth hook failed: %s", result)
      return false
    end
    if result == true then
      self._authenticated = true
    end
  end

  -- Authenticate only if agent supports it (authMethods not empty)
  if not self._authenticated then
    local auth_methods = (self._agent_info and self._agent_info.authMethods) or {}
    if #auth_methods > 0 then
      local wanted = self.adapter_modified.defaults.auth_method
      local method_id
      for _, m in ipairs(auth_methods) do
        if m.id == wanted then
          method_id = m.id
          break
        end
      end
      method_id = method_id or (auth_methods[1] and auth_methods[1].id)

      if method_id then
        local ok = self:send_rpc_request(METHODS.AUTHENTICATE, { methodId = method_id })
        if not ok then
          log:error("[acp::_authenticate] Failed to authenticate with method %s", method_id)
          return false
        end
      end
    end
    self._authenticated = true
  end

  return true
end

---Create or load a session
---@return boolean success
function Connection:_establish_session()
  local can_load = self._agent_info
    and self._agent_info.agentCapabilities
    and self._agent_info.agentCapabilities.loadSession

  local session_args = {
    cwd = vim.fn.getcwd(),
    mcpServers = self.adapter_modified.defaults.mcpServers,
  }

  if self.session_id and can_load then
    local ok = self:send_rpc_request(
      METHODS.SESSION_LOAD,
      vim.tbl_extend("force", session_args, { sessionId = self.session_id })
    )
    if ok == nil then
      can_load = false
    end
  end

  if not self.session_id or not can_load then
    local new_session = self:send_rpc_request(METHODS.SESSION_NEW, session_args)
    if not new_session or not new_session.sessionId then
      log:error("[acp::_establish_session] Failed to create session")
      return false
    end
    self.session_id = new_session.sessionId

    if new_session.modes then
      self._modes = new_session.modes
      log:debug("[acp::_establish_session] Available modes: %s", new_session.modes)
    end
    if new_session.models then
      self._models = new_session.models
      log:debug("[acp::_establish_session] Available models: %s", new_session.models)
    end
  end

  return true
end

---Apply the default model from the adapter config
---@return boolean
function Connection:apply_default_model()
  if not self._models then
    return false
  end

  local default_model = self.adapter_modified
    and self.adapter_modified.defaults
    and self.adapter_modified.defaults.model
  if not default_model then
    return false
  end

  -- Support function values for default model
  if type(default_model) == "function" then
    default_model = default_model(self.adapter_modified)
  end

  if type(default_model) ~= "string" or default_model == "" then
    return false
  end

  -- Check if the requested model is available
  local model_id = nil
  for _, model in ipairs(self._models.availableModels or {}) do
    -- Match by modelId and then by partial name match (e.g., "opus" matches "claude-opus-4")
    if model.modelId == default_model then
      model_id = model.modelId
      break
    elseif model.modelId:lower():find(default_model:lower(), 1, true) then
      model_id = model.modelId
      break
    end
  end

  if not model_id then
    log:warn("[acp::apply_default_model] Model `%s` not found in available models", default_model)
    return false
  end

  if model_id == self._models.currentModelId then
    log:debug("[acp::apply_default_model] Model `%s` is already selected", model_id)
    return true
  end

  return self:set_model(model_id)
end

---Create the ACP process
---@return boolean success
function Connection:start_agent_process()
  local adapter = self:prepare_adapter()
  self.adapter_modified = adapter

  if adapter.handlers and adapter.handlers.setup then
    if not adapter.handlers.setup(adapter) then
      log:error("[acp::start_agent_process] Adapter setup failed")
      return false
    end
  end

  self._state.line_buffer:reset()

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

  local id = self._state.id_gen:next()
  local request = jsonrpc.request(id, method, params)

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
  self:write_message(self.methods.encode(jsonrpc.result(id, result)) .. "\n")
end

---Send an error response to the ACP process
---@param id number
---@param message string
---@param code? number
---@return nil
function Connection:send_error(id, message, code)
  self:write_message(self.methods.encode(jsonrpc.error(id, message, code or jsonrpc.errors.INTERNAL)) .. "\n")
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
  adapter = adapter_utils.get_env_vars(adapter, { timeout = config.adapters.opts.cmd_timeout })
  adapter.parameters = adapter_utils.set_env_vars(adapter, adapter.parameters)
  adapter.defaults.auth_method = adapter_utils.set_env_vars(adapter, adapter.defaults.auth_method)
  adapter.defaults.mcpServers = adapter_utils.set_env_vars(adapter, adapter.defaults.mcpServers)
  adapter.command = adapter_utils.set_env_vars(adapter, adapter.commands.selected or adapter.commands.default)

  return adapter
end

---Disconnect and clean up the ACP process
---@return nil
function Connection:disconnect()
  assert(self._state.handle):kill(9)
end

---Process the output - JSON-RPC doesn't guarantee message boundaries align
---with I/O boundaries, so we need to buffer and handle this carefully.
---@param data string
function Connection:buffer_stdout_and_dispatch(data)
  self._state.line_buffer:push(data, function(line)
    self:handle_rpc_message(line)
  end)
end

---Handle incoming JSON message
---@param line string
function Connection:handle_rpc_message(line)
  if not line or line == "" then
    return
  end

  -- If it doesn't look like JSON-RPC, skip it
  if not line:match("^%s*{") then
    return
  end

  local ok, message = jsonrpc.decode(line, self.methods.decode)
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

  if message.error and message.error.code ~= jsonrpc.errors.INTERNAL then
    log:error("[acp::handle_rpc_message] Error: %s", message.error)
  end
end

---Handle response to our request
---@param response table
function Connection:store_rpc_response(response)
  if response.error then
    self.pending_responses[response.id] = { nil, response.error }

    -- Sometimes errors are passed as part of the response so we need to handle them
    if self._active_prompt and self._active_prompt.handle_error then
      self.methods.schedule(function()
        local error_msg = response.error.message or "Unknown error"
        if response.error.data and response.error.data.error then
          error_msg = response.error.data.error
        end

        self._active_prompt:handle_error(error_msg)
      end)
    end
    return
  end
  self.pending_responses[response.id] = { response.result, nil }
end

---Send a notification to the ACP process
---@param method string
---@param params table
---@return nil
function Connection:send_notification(method, params)
  self:write_message(self.methods.encode(jsonrpc.notification(method, params)) .. "\n")
end

---@private
local DISPATCH = {
  [METHODS.SESSION_UPDATE] = function(self, m)
    if m.params.update and m.params.update.sessionUpdate == "available_commands_update" then
      self:handle_available_commands_update(m.params.sessionId, m.params.update.availableCommands)
    elseif m.params.update and m.params.update.sessionUpdate == "current_mode_update" then
      self:handle_current_mode_update(m.params.sessionId, m.params.update.modeId)
    elseif self._active_prompt then
      self._active_prompt:handle_session_update(m.params.update)
    end
  end,
  [METHODS.SESSION_REQUEST_PERMISSION] = function(self, m)
    if self._active_prompt then
      self._active_prompt:handle_permission_request(m.id, m.params)
    end
  end,
  [METHODS.FS_READ_TEXT_FILE] = function(self, m)
    self:handle_fs_read_text_file_request(m.id, m.params)
  end,
  [METHODS.FS_WRITE_TEXT_FILE] = function(self, m)
    self:handle_fs_write_file_request(m.id, m.params)
  end,
}

---Handle incoming requests and notifications from the ACP agent process
---@param notification? table
function Connection:handle_incoming_request_or_notification(notification)
  if type(notification) ~= "table" or type(notification.method) ~= "string" then
    return
  end

  local sid = notification.params and notification.params.sessionId
  local is_request = notification.id ~= nil
  if sid and self.session_id and sid ~= self.session_id then
    if is_request then
      return self:send_error(notification.id, "invalid sessionId", jsonrpc.errors.INVALID_PARAMS)
    end
    return
  end

  local handler = DISPATCH[notification.method]
  if handler then
    return handler(self, notification)
  end
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
    self._state.handle:write(data)
  end)

  if not ok then
    log:error("[acp::write_message] Failed to send data: %s", err)
    return false
  end

  return true
end

---Check if params contain a mismatched sessionId
---@param params table
---@return boolean valid true if sessionId matches or is absent
function Connection:_has_valid_session_id(params)
  return not params.sessionId or not self.session_id or params.sessionId == self.session_id
end

---Handle fs/read_text_file requests
---@param id number
---@param params { path: string, sessionId?: string, limit?: number|nil, line?: number|nil }
---@return nil
function Connection:handle_fs_read_text_file_request(id, params)
  if not id or type(params) ~= "table" then
    return
  end

  if not self:_has_valid_session_id(params) then
    return self:send_error(id, "invalid sessionId for fs/read_text_file", jsonrpc.errors.INVALID_PARAMS)
  end

  local path = params.path
  if type(path) ~= "string" then
    return self:send_error(id, "invalid params", jsonrpc.errors.INVALID_PARAMS)
  end

  local fs = require("codecompanion.interactions.chat.acp.fs")
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

  if not self:_has_valid_session_id(params) then
    return self:send_error(id, "invalid sessionId for fs/write_text_file", jsonrpc.errors.INVALID_PARAMS)
  end

  local path = params.path
  local content = params.content or ""
  if type(path) ~= "string" or type(content) ~= "string" then
    return self:send_error(id, "invalid params", jsonrpc.errors.INVALID_PARAMS)
  end

  local fs = require("codecompanion.interactions.chat.acp.fs")
  local ok, err = fs.write_text_file(path, content)
  if ok then
    self:send_result(id, vim.NIL)
    local info = { path = path, bytes = #content, sessionId = params.sessionId }
    if self._active_prompt and self._active_prompt.handlers and self._active_prompt.handlers.write_text_file then
      pcall(self._active_prompt.handlers.write_text_file, info)
    end
  else
    self:send_error(id, ("fs/write_text_file failed: %s"):format(err or "unknown"))
  end
end

---Handle available_commands_update notification
---@param session_id string
---@param commands ACP.availableCommands
---@return nil
function Connection:handle_available_commands_update(session_id, commands)
  if not session_id then
    return
  end

  if type(commands) ~= "table" then
    return log:error("[acp::handle_available_commands_update] Invalid commands format")
  end

  local acp_commands = require("codecompanion.interactions.chat.acp.commands")
  acp_commands.register_commands(session_id, commands)
end

---Handle current_mode_update notification
---@param session_id string
---@param mode_id string
---@return nil
function Connection:handle_current_mode_update(session_id, mode_id)
  if not session_id then
    return
  end

  if session_id ~= self.session_id then
    return
  end

  if not self._modes then
    return
  end

  if type(mode_id) ~= "string" then
    return log:error("[acp::handle_current_mode_update] Invalid mode_id format: %d", mode_id)
  end

  -- Update the current mode
  self._modes.currentModeId = mode_id
end

---Handle process exit
---@param code number
---@param signal number
function Connection:handle_process_exit(code, signal)
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

---Get the available session modes
---@return table|nil modes {currentModeId: string, availableModes: table[]} or nil if not supported
function Connection:get_modes()
  return self._modes
end

---Set the current session mode
---@param mode_id string The ID of the mode to switch to
---@return boolean success
function Connection:set_mode(mode_id)
  return self:_set_session_property({
    value = mode_id,
    collection = self._modes,
    items_key = "availableModes",
    current_key = "currentModeId",
    id_key = "id",
    rpc_method = METHODS.SESSION_SET_MODE,
    rpc_param_key = "modeId",
    label = "mode",
  })
end

---Get the available models
---@return table|nil models {currentModelId: string, availableModels: table[]} or nil if not supported
function Connection:get_models()
  return self._models
end

---Set a model
---@param model_id string The ID of the model to switch to
---@return boolean success
function Connection:set_model(model_id)
  return self:_set_session_property({
    value = model_id,
    collection = self._models,
    items_key = "availableModels",
    current_key = "currentModelId",
    id_key = "modelId",
    rpc_method = METHODS.SESSION_SET_MODEL,
    rpc_param_key = "modelId",
    label = "model",
  })
end

---Shared helper to validate and set a session property (mode or model)
---@param args { value: string, collection: table|nil, items_key: string, current_key: string, id_key: string, rpc_method: string, rpc_param_key: string, label: string }
---@return boolean success
function Connection:_set_session_property(args)
  if not self.session_id then
    log:error("[acp::set_%s] Connection not established", args.label)
    return false
  end

  if not args.collection then
    log:error("[acp::set_%s] Agent does not support changing %ss", args.label, args.label)
    return false
  end

  local valid = false
  for _, item in ipairs(args.collection[args.items_key] or {}) do
    if item[args.id_key] == args.value then
      valid = true
      break
    end
  end

  if not valid then
    log:error("[acp::set_%s] Invalid %s ID: %s", args.label, args.label, args.value)
    return false
  end

  if args.value == args.collection[args.current_key] then
    return false
  end

  local ok = self:send_rpc_request(args.rpc_method, {
    [args.rpc_param_key] = args.value,
    sessionId = self.session_id,
  })

  if not ok then
    log:error("[acp::set_%s] Failed to set %s to %s", args.label, args.label, args.value)
    return false
  end

  args.collection[args.current_key] = args.value
  log:debug("[acp::set_%s] Changed %s to %s", args.label, args.label, args.value)

  return true
end

return Connection
