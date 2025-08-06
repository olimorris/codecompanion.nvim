--[[
==========================================================
  File:       codecompanion/acp.lua
  Author:     Oli Morris
----------------------------------------------------------
  Description:
    This module implements the ACP client for CodeCompanion.
    It handles the connection to the ACP process, manages sessions,
    and provides methods for making requests and handling responses.
    The client uses JSON-RPC 2.0 for communication with the ACP server.

  References:
    - https://www.jsonrpc.org/specification
==========================================================
--]]

local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

---@class CodeCompanion.ACPClient
---@field adapter CodeCompanion.ACPAdapter The ACP adapter used by the client
---@field job {handle: table, next_id: integer, pending: table, stdout: string, stdout_buffer: string}|nil The job handle for the ACP process
---@field methods table Static methods for testing/mocking
---@field opts table Client options
---@field session_id string|nil The session ID for the current ACP session
---@field _authenticated boolean Has the client has been authenticated
---@field _current_request table|nil Current request options for events
---@field _initialized boolean Has the client has been initialized
---@field _streaming_started boolean Has the client has been initialized
local Client = {}
Client.static = {}

-- Define our static methods for the ACP client making it easier to mock and test
Client.static.methods = {
  confirm = { default = vim.fn.confirm },
  decode = { default = vim.json.decode },
  encode = { default = vim.json.encode },
  jobstart = { default = vim.system },
  schedule = { default = vim.schedule },
  schedule_wrap = { default = vim.schedule_wrap },
}

---Allow for easier testing/mocking of the static methods
---@param opts? table
---@return table
local function transform_static_methods(opts)
  local ret = {}
  for k, v in pairs(Client.static.methods) do
    if opts and opts[k] ~= nil then
      ret[k] = opts[k]
    else
      ret[k] = v.default
    end
  end
  return ret
end

---@class CodeCompanion.ACPClientArgs
---@field adapter CodeCompanion.ACPAdapter
---@field session_id? string The session ID to load, if any
---@field opts? table

---@param args CodeCompanion.ACPClientArgs
---@return CodeCompanion.ACPClient
function Client.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    job = { handle = nil, next_id = 1, pending = {}, stdout = "" },
    methods = transform_static_methods(args.opts),
    opts = args.opts or {},
    session_id = args.session_id or nil,
  }, { __index = Client })
end

---Setup the adapter, ensuring the environment variables are set correctly
---@param adapter CodeCompanion.ACPAdapter
---@return CodeCompanion.ACPAdapter
local function setup_adapter(adapter)
  adapter = vim.deepcopy(adapter)
  adapter = adapter_utils.get_env_vars(adapter)
  adapter.parameters = adapter_utils.set_env_vars(adapter, adapter.parameters)
  adapter.defaults.auth_method = adapter_utils.set_env_vars(adapter, adapter.defaults.auth_method)
  adapter.defaults.mcpServers = adapter_utils.set_env_vars(adapter, adapter.defaults.mcpServers)
  adapter.command = adapter_utils.set_env_vars(adapter, adapter.command)

  return adapter
end

---Connect to ACP process and establish session
---@return string The session ID of the connected session
function Client:connect()
  if not self.job.handle then
    self:_create_job()
  end

  local adapter = setup_adapter(self.adapter)

  if not self._initialized then
    local initialized = self:_make_rpc_call("initialize", adapter.parameters)
    if not initialized then
      self.opts.status = "error"
      return log:error("[acp::connect] Failed to initialize ACP client")
    end
    self._initialized = true
    log:debug("ACP client initialized")
  end

  if not self._authenticated then
    local authenticated = self:_make_rpc_call("authenticate", { methodId = adapter.defaults.auth_method })
    if not authenticated then
      self.opts.status = "error"
      return log:error("[acp::connect] Failed to authenticate ACP client")
    end
    self._authenticated = true
    log:debug("ACP client authenticated")
  end

  -- Try loading a session if session_id is provided
  if self.session_id then
    local session_loaded = self:_make_rpc_call("session/load", {
      cwd = vim.fn.getcwd(),
      mcpServers = self.adapter.defaults.mcpServers or {},
      sessionId = self.session_id,
    })
    if session_loaded then
      log:debug("Loaded existing ACP session: %s", self.session_id)
      return self.session_id
    end
  end

  -- Otherwise, create a new session
  local new_session = self:_make_rpc_call("session/new", {
    cwd = vim.fn.getcwd(),
    mcpServers = self.adapter.defaults.mcpServers or {},
  })

  if not new_session or not new_session.sessionId then
    self.opts.status = "error"
    return log:error("[acp::connect] Failed to create new session")
  end

  self.session_id = new_session.sessionId
  log:debug("Created new ACP session: %s", self.session_id)
  return self.session_id
end

---Create the job for the ACP process
---@return nil
function Client:_create_job()
  local adapter = setup_adapter(self.adapter)

  log:debug("Starting ACP process with command: %s", adapter.command)

  if adapter.handlers and adapter.handlers.setup then
    local ok = adapter.handlers.setup(adapter)
    if not ok then
      return log:error("[acp::_create_job] Failed to setup adapter")
    end
  end

  -- Buffer for accumulating partial JSON
  self.job.stdout_buffer = ""

  local ok, sysobj_or_err = pcall(
    self.methods.jobstart,
    adapter.command,
    {
      stdin = true,
      stdout = self.methods.schedule_wrap(function(err, data)
        if err then
          return log:error("[acp::_create_job] ACP stdout error: %s", err)
        end
        if data then
          self:_on_stdout(data)
        end
      end),
      stderr = self.methods.schedule_wrap(function(err, data)
        if err then
          return log:error("[acp::_create_job] ACP stderr error: %s", err)
        end
        if data then
          self:_on_stderr(data)
        end
      end),
      env = adapter.env_replaced or {},
      cwd = vim.fn.getcwd(),
    },
    self.methods.schedule_wrap(function(obj)
      self:_on_exit(obj.code, obj.signal)
    end)
  )

  if not ok then
    local err = sysobj_or_err
    log:error("[acp::_create_job] Failed to start ACP process: " .. (err or "unknown error"))
  end

  -- I prefer thinking of this as a job...
  self.job.handle = sysobj_or_err

  log:debug("ACP process started with vim.system")
end

---Make a synchronous RPC call (blocks until response)
---@param method string
---@param params table
---@return table|nil
function Client:_make_rpc_call(method, params)
  if not self.job.handle then
    self.opts.status = "error"
    return log:error("[acp::_make_rpc_call] ACP client not running")
  end

  local id = self.job.next_id
  self.job.next_id = id + 1

  local request = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  local json = self.methods.encode(request) .. "\n"
  log:debug("Sending sync request: %s", json:gsub("\n", "\\n"))

  if not self:_send_data(json) then
    self.opts.status = "error"
    return log:error("[acp::_make_rpc_call] Failed to send request")
  end
  log:debug("Request sent successfully, waiting for response with ID: %d", id)

  local start_time = vim.uv.hrtime()
  local timeout = self.adapter.defaults.timeout or 2e4 -- Default to 20 seconds if not set

  while true do
    vim.wait(10) -- NOTE: This is required! Do not remove!

    -- Check for a response
    if self.job.pending[id] then
      local result, err = unpack(self.job.pending[id])
      self.job.pending[id] = nil
      log:debug("Received response for ID %d: result=%s, err=%s", id, result, err)
      if err then
        return log:error("[acp::_make_rpc_call] Error making RPC call: %s", err)
      end
      return result
    end

    -- Timeout check
    local elapsed = (vim.uv.hrtime() - start_time) / 1e6
    if elapsed > timeout then
      return log:error(
        "[acp::_make_rpc_call] Timeout waiting for response to %s (ID: %d, elapsed: %dms)",
        method,
        id,
        elapsed
      )
    end
  end
end

---Handle stdout data and route messages
---@param data table
---@return nil
function Client:_on_stdout(data)
  if not data or data == "" then
    return
  end

  log:debug("Raw stdout data received: %s", data)

  -- Add any new data to the stdout buffer
  self.job.stdout_buffer = self.job.stdout_buffer .. data

  -- There's a chance the agent may return incomplete JSON. So to handle this
  -- we need to process the stdout buffer line by line
  while true do
    local newline_pos = self.job.stdout_buffer:find("\n")
    if not newline_pos then
      break
    end

    local line = self.job.stdout_buffer:sub(1, newline_pos - 1)
    self.job.stdout_buffer = self.job.stdout_buffer:sub(newline_pos + 1)

    line = vim.trim(line)
    if line ~= "" then
      self:_process_json(line)
    end
  end
end

---Process a complete JSON line
---@param line string
---@return nil
function Client:_process_json(line)
  log:debug("Processing JSON line: %s", line)

  local ok, decoded = pcall(self.methods.decode, line)
  if not ok then
    return log:error("[acp::_process_json] Failed to parse JSON: %s", line)
  end

  log:debug("Successfully parsed JSON: %s", decoded)

  if decoded.id then
    self:_handle_response(decoded)

    -- Check for the streaming coming to an end
    if decoded.result == vim.NIL then
      self.methods.schedule(function()
        self:_on_done()
      end)
    end
  elseif decoded.method then
    self:_handle_notification(decoded)
  end

  if decoded.error then
    if self._callback then
      self._callback(decoded.error, nil) -- Pass error as first param
    end
    self.methods.schedule(function()
      self.opts.status = "error"
      self:_on_done()
    end)
    return log:error("[acp::_process_json] Error in response: %s", decoded.error)
  end
end

---Handle the completion of a request
---@return nil
function Client:_on_done()
  if not self._done then
    return
  end

  if self._current_request then
    self._current_request.status = self._current_request.status or "success"
    if not self._current_request.silent then
      util.fire("RequestFinished", self._current_request)
    end
  end

  self._done()
  self._done = nil
  self._current_request = nil
end

---Method for when the ACP client exits
---@param code integer
---@param signal integer
---@return nil
function Client:_on_exit(code, signal)
  log:debug("ACP client %s exited with code: %d, signal: %d", self.adapter.name, code, signal or 0)

  -- Reset state
  self.job = {}
  self._current_request = nil
  self._initialized = false
  self._authenticated = false

  if self.adapter.handlers and self.adapter.handlers.on_exit then
    self.adapter.handlers.on_exit(self.adapter, code)
  end
end

---Handle any notifications that come from the RPC server
---@param data table
function Client:_handle_notification(data)
  if data.method == "session/request_permission" then
    self:_permission_request(data.id, data.params)
  elseif data.method == "session/update" then
    if self._current_request and not self._streaming_started then
      self._streaming_started = true
      if not self._current_request.silent then
        util.fire("RequestStreaming", self._current_request)
      end
    end
    if self._callback then
      self._callback(nil, data.params)
    end
  end
end

---Handle JSON-RPC responses (replies to our requests)
---@param response table
function Client:_handle_response(response)
  log:debug("Storing response for ID %d", response.id)

  if response.error then
    self.job.pending[response.id] = { nil, response.error }
    log:error("RPC error for ID %d: %s", response.id, response.error)
  else
    self.job.pending[response.id] = { response.result, nil }
    log:debug("RPC success for ID %d", response.id)
  end
end

---Handle permission requests from agent
---@param id integer|nil
---@param params table
function Client:_permission_request(id, params)
  local tool_call = params.toolCall
  local options = params.options

  -- Build choices for vim.fn.confirm
  local choices = {}
  local option_map = {}

  for i, option in ipairs(options) do
    table.insert(choices, "&" .. option.label)
    option_map[i] = option.optionId
  end

  local choice_str = table.concat(choices, "\n")
  local choice =
    self.methods.confirm(string.format("Tool Permission Request:\n%s", tool_call.label), choice_str, 1, "Question")

  -- Send permission response
  local option_id = choice > 0 and option_map[choice] or "cancel"

  if id then
    self:_send_response(id, { optionId = option_id })
  end
end

---Send JSON-RPC response
---@param id integer
---@param result table
function Client:_send_response(id, result)
  if not self.job.handle then
    return
  end

  local response = {
    jsonrpc = "2.0",
    id = id,
    result = result,
  }

  local json_str = self.methods.encode(response) .. "\n"
  log:trace("Sending response: %s", json_str:gsub("\n", "\\n"))
  self.methods.chansend(self.job.handle, json_str)
end

---Handle stderr data
---@param data table
---@return nil
function Client:_on_stderr(data)
  if data and data ~= "" then
    for line in data:gmatch("[^\r\n]+") do
      if line ~= "" then
        log:debug("ACP stderr (%s): %s", self.adapter.name, line)
      end
    end
  end
end

---Send data to the process
---@param data string
---@return boolean
function Client:_send_data(data)
  if not self.job.handle then
    log:error("[acp::_send_data] Cannot send data: ACP process not running")
    return false
  end

  log:debug("Sending data: %s", data:gsub("\n", "\\n"))

  local ok, err = pcall(function()
    self.job.handle:write(data)
  end)

  if not ok then
    log:error("[acp::_send_data] Failed to send data to ACP process: %s", err)
    return false
  end

  return true
end

---Send prompt to the session
---@param payload table
---@param actions table
---@param opts table
---@return table job-like object for compatibility
function Client:request(payload, actions, opts)
  payload = self.adapter.handlers.form_messages(self.adapter, payload)

  -- We store the objects on the object so they can be called by the job, later
  self._callback = actions.callback --[[@type function]]
  self._done = actions.done --[[@type function]]

  self._current_request = vim.deepcopy(opts)
  self._current_request.id = math.random(10000000)
  self._current_request.adapter = {
    name = self.adapter.name,
    formatted_name = self.adapter.formatted_name,
    type = self.adapter.type,
    model = nil,
  }

  -- Send prompt (async)
  local prompt_req = {
    jsonrpc = "2.0",
    id = self.job.next_id,
    method = "session/prompt",
    params = {
      sessionId = self.session_id,
      prompt = payload,
    },
  }

  self.job.next_id = self.job.next_id + 1
  local json_str = self.methods.encode(prompt_req) .. "\n"
  log:trace("Sending prompt: %s", json_str:gsub("\n", "\\n"))

  if self._current_request and not self._current_request.silent then
    util.fire("RequestStarted", self._current_request)
  end

  self._streaming_started = false
  self:_send_data(json_str)
  self.state = "prompting"

  -- Return job-like object for compatibility with the http adapter
  return {
    shutdown = function()
      self:shutdown()
    end,
  }
end

---Cancel and shutdown the current request
function Client:shutdown()
  if self.state == "prompting" then
    local cancel_req = {
      jsonrpc = "2.0",
      id = self.job.next_id,
      method = "session/cancelled",
      params = { sessionId = self.session_id },
    }

    self.job.next_id = self.job.next_id + 1
    local json_str = self.methods.encode(cancel_req) .. "\n"
    self:_send_data(json_str)

    if self._current_request and not self._current_request.silent then
      self._current_request.status = "cancelled"
      util.fire("RequestFinished", self._current_request)
    end

    self.state = "ready"
    self._callback = nil
    self._done = nil
    self._current_request = nil
  end
end

return Client
