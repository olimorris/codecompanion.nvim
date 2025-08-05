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
---@field job {handle: integer, next_id: integer, pending: table, stdout: string}|nil The job handle for the ACP process
---@field methods table Static methods for testing/mocking
---@field opts table Client options
---@field session_id string|nil The session ID for the current ACP session
---@field _initialized boolean Has the client has been initialized
---@field _authenticated boolean Has the client has been authenticated
local Client = {}
Client.static = {}

-- Define our static methods for the ACP client making it easier to mock and test
Client.static.methods = {
  chansend = { default = vim.fn.chansend },
  decode = { default = vim.json.decode },
  encode = { default = vim.json.encode },
  jobstart = { default = vim.fn.jobstart },
  jobstop = { default = vim.fn.jobstop },
  schedule = { default = vim.schedule },
  confirm = { default = vim.fn.confirm },
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
      self:_on_done()
      return log:error("[acp::connect] Failed to initialize ACP client")
    end
    self._initialized = true
    log:debug("ACP client initialized")
  end

  if not self._authenticated then
    local authenticated = self:_make_rpc_call("authenticate", { methodId = adapter.defaults.auth_method })
    if not authenticated then
      self.opts.status = "error"
      self:_on_done()
      return log:error("[acp::connect] Failed to authenticate ACP client")
    end
    self._authenticated = true
    log:debug("ACP client authenticated")
  end

  -- Try loading a session if session_id is provided
  if self.session_id then
    local session_loaded = self:_make_rpc_call("session/load", { sessionId = self.session_id })
    if session_loaded then
      log:debug("Loaded existing ACP session: %s", self.session_id)
      return self.session_id
    end
  end

  -- Otherwise, create a new session
  local new_session = self:_make_rpc_call("session/new", {
    cwd = vim.fn.getcwd(),
    mcpServers = {},
  })

  if not new_session or not new_session.sessionId then
    self.opts.status = "error"
    self:_on_done()
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
  log:debug("Environment variables: %s", adapter.env_replaced)

  if adapter.handlers and adapter.handlers.setup then
    local ok = adapter.handlers.setup(adapter)
    if not ok then
      error("Failed to setup adapter")
    end
  end

  local job_opts = {
    stdin = "pipe",
    stdout = "pipe",
    stderr = "pipe",
    env = adapter.env_replaced or {},
    on_stdout = function(_, data, _)
      self:_on_stdout(data)
    end,
    on_stderr = function(_, data, _)
      self:_handle_stderr(data)
    end,
    on_exit = function(_, code, _)
      self:_on_exit(code)
    end,
  }

  self.job.handle = self.methods.jobstart(adapter.command, job_opts)
  if self.job.handle <= 0 then
    error("Failed to start ACP process: " .. adapter.name)
  end

  log:debug("ACP process started with job handle: %d", self.job.handle)
end

---Make a synchronous RPC call (blocks until response)
---@param method string
---@param params table
---@return table|nil
function Client:_make_rpc_call(method, params)
  if not self.job.handle then
    self.opts.status = "error"
    self:_on_done()
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

  --TODO: Remove this line break
  local json = self.methods.encode(request) .. "\n"
  log:debug("Sending sync request: %s", json:gsub("\n", "\\n"))

  self.methods.chansend(self.job.handle, json)
  log:debug("Request sent successfully, waiting for response with ID: %d", id)

  local start_time = vim.loop.hrtime()
  local timeout = self.adapter.defaults.timeout or 20000 -- Default to 20 seconds if not set

  while true do
    vim.wait(20) -- Apply a small 10ms buffer

    -- Check for a response
    if self.job.pending[id] then
      local result, err = unpack(self.job.pending[id])
      self.job.pending[id] = nil
      log:debug("Received response for ID %d: result=%s, err=%s", id, result, err)
      if err then
        self.opts.status = "error"
        self:_on_done()
        return log:error("[acp::_make_rpc_call] Error making RPC call: %s", err)
      end
      return result
    end

    -- Timeout check
    local elapsed = (vim.loop.hrtime() - start_time) / 1000000
    if elapsed > timeout then
      self.opts.status = "error"
      self:_on_done()
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
function Client:_on_stdout(data)
  log:debug("Raw stdout data received: %s", data)

  for _, chunk in ipairs(data) do
    if chunk == "" then
      goto continue
    end

    log:debug("Processing stdout chunk: %s", chunk)

    chunk = vim.trim(chunk)
    if chunk == "" then
      goto continue
    end

    local ok, decoded_chunk = pcall(self.methods.decode, chunk)
    if not ok then
      goto continue
    end

    if decoded_chunk then
      log:debug("Successfully parsed complete JSON: %s", decoded_chunk)

      if decoded_chunk.id then
        self:_handle_response(decoded_chunk)

        -- Detect the final response
        if decoded_chunk.result == vim.NIL then
          if self._done then
            self:_on_done()
          end
        end
      elseif decoded_chunk.method then
        self:_handle_notification(decoded_chunk)
      end

      if decoded_chunk.error then
        self.opts.status = "error"
        self:_on_done()
        return log:error("[acp::_on_stdout] Error in ACP response: %s", decoded_chunk.error)
      end
    end

    ::continue::
  end
end

---Handle the completion of a request
---@return nil
function Client:_on_done()
  if self.opts then
    if not self.opts.status then
      self.opts.status = "success"
    end
    if not self.opts.silent then
      util.fire("RequestFinished", self.opts)
    end
  end

  self.opts = {}
  self._done()
end

---Method for when the ACP client exits
---@param code integer
function Client:_on_exit(code)
  log:debug("ACP client %s exited with code: %d", self.adapter.name, code)

  -- Reset state
  self.job = {}
  self.opts = {}
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
    if self._callback then
      self.methods.schedule(function()
        self._callback(data.method, data.params)
      end)
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
function Client:_handle_stderr(data)
  for _, err in ipairs(data) do
    if err ~= "" then
      log:debug("ACP stderr (%s): %s", self.adapter.name, err)
    end
  end
end

---Send prompt to the session
---@param payload table
---@param actions table
---@return table job-like object for compatibility
function Client:request(payload, actions)
  --TODO: use adapter form_messages handler
  -- payload = self.client.adapter.handlers.form_messages(payload, opts)
  local acp_prompt = {}
  for _, message in ipairs(payload) do
    if message.role == "user" or message.role == "assistant" then
      table.insert(acp_prompt, {
        type = "text",
        text = message.content,
      })
    end
  end

  -- We store the objects on the object so they can be called by the job, later
  self._callback = actions.callback --[[@type function]]
  self._done = actions.done --[[@type function]]

  -- Send prompt (async)
  local prompt_req = {
    jsonrpc = "2.0",
    id = self.job.next_id,
    method = "session/prompt",
    params = {
      sessionId = self.session_id,
      prompt = acp_prompt,
    },
  }

  self.job.next_id = self.job.next_id + 1
  local json_str = self.methods.encode(prompt_req) .. "\n"
  log:trace("Sending prompt: %s", json_str:gsub("\n", "\\n"))

  if self.opts and not self.opts.silent then
    util.fire("RequestStarted", self.opts)
  end
  self.methods.chansend(self.job.handle, json_str)

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
    self.methods.chansend(self.job.handle, json_str)

    self.state = "ready"
    self._callback = nil
  end
end

return Client
