local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.ACPClient
---@field adapter CodeCompanion.ACPAdapter The ACP adapter used by the client
---@field job {handle: integer, next_id: integer, pending: table, stdout: string}|nil The job handle for the ACP process
---@field session {id: string|nil, state: "disconnected"|"initializing"|"authenticating"|"ready"|"prompting"} Session management
---@field opts nil|table
---@field methods table
---@field current_request {callback: function, done: function, id: integer}|nil

---@class CodeCompanion.ACPClient
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
---@field opts? table

---@param args CodeCompanion.ACPClientArgs
function Client.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    job = {},
    session = { id = nil, state = "disconnected" },
    methods = transform_static_methods(args.opts),
    opts = args.opts or {},
    current_request = nil,
  }, { __index = Client })
end

---Start the ACP process
---@return CodeCompanion.ACPClient
function Client:start()
  if self.job.handle then
    log:debug("ACP client already running")
    return self
  end

  local adapter = vim.deepcopy(self.adapter)
  adapter = adapter_utils.get_env_vars(adapter)
  local command = adapter_utils.set_env_vars(adapter, adapter.command)

  if adapter.handlers and adapter.handlers.setup then
    local ok = adapter.handlers.setup(adapter)
    if not ok then
      return log:error("Failed to setup adapter")
    end
  end

  local job_opts = {
    stdin = "pipe",
    stdout = "pipe",
    stderr = "pipe",
    env = adapter.env_replaced or {},
    on_stdout = function(_, data, _)
      self:_handle_stdout(data)
    end,
    on_stderr = function(_, data, _)
      self:_handle_stderr(data)
    end,
    on_exit = function(_, code, _)
      self:_handle_exit(code)
    end,
  }

  self.job.handle = self.methods.jobstart(command, job_opts)
  self.job.next_id = 1
  self.job.pending = {}
  self.job.stdout = ""

  if self.job.handle <= 0 then
    log:error("Failed to start ACP client: %s", self.adapter.name)
    return self
  end

  log:debug("ACP process started with job handle: %d", self.job.handle)
  return self
end

---Main request interface matching HTTP client
---@param payload { messages: table, tools: table|nil }
---@param actions { callback: function, done: function }
---@param opts? table
---@return table|nil
function Client:request(payload, actions, opts)
  opts = opts or {}

  -- Store current request for streaming callbacks
  self.current_request = {
    callback = actions.callback,
    done = actions.done,
    id = math.random(10000000),
  }

  -- Start process if not running
  if not self.job.handle then
    self:start()
  end

  -- Ensure we have a ready session
  self:_ensure_session(function(err)
    if err then
      return actions.callback(err, nil)
    end

    -- Convert payload to ACP format and send prompt
    self:_send_prompt(payload, actions, opts)
  end)

  -- Return a job-like object for compatibility
  return {
    shutdown = function()
      self:_cancel_current_request()
    end,
  }
end

---Ensure we have a ready session (initialize -> authenticate -> session/new)
---@param callback function
function Client:_ensure_session(callback)
  if self.session.state == "ready" and self.session.id then
    return callback(nil)
  end

  if self.session.state ~= "disconnected" then
    -- Session in progress, wait
    return vim.defer_fn(function()
      self:_ensure_session(callback)
    end, 100)
  end

  self.session.state = "initializing"

  -- Initialize
  self:_rpc_request("initialize", self.adapter.parameters or {}, function(result, err)
    if err then
      self.session.state = "disconnected"
      return callback({ message = "Initialization failed", stderr = vim.json.encode(err) })
    end

    self.session.state = "authenticating"

    -- Authenticate (hardcoded to API key for now)
    self:_rpc_request("authenticate", { methodId = "gemini-api-key" }, function(auth_result, auth_err)
      if auth_err then
        self.session.state = "disconnected"
        return callback({ message = "Authentication failed", stderr = vim.json.encode(auth_err) })
      end

      -- Create new session
      local cwd = vim.fn.getcwd()
      self:_rpc_request("session/new", { cwd = cwd, mcpServers = {} }, function(session_result, session_err)
        if session_err then
          self.session.state = "disconnected"
          return callback({ message = "Session creation failed", stderr = vim.json.encode(session_err) })
        end

        self.session.id = session_result.sessionId
        self.session.state = "ready"
        log:debug("ACP session ready: %s", self.session.id)
        callback(nil)
      end)
    end)
  end)
end

---Send prompt to ACP and handle streaming
---@param payload table
---@param actions table
---@param opts table
function Client:_send_prompt(payload, actions, opts)
  -- Convert messages to ACP format
  local acp_prompt = {}
  for _, message in ipairs(payload.messages) do
    if message.role == "user" or message.role == "assistant" then
      table.insert(acp_prompt, {
        type = "text",
        text = message.content,
      })
    end
  end

  self.session.state = "prompting"

  self:_rpc_request("session/prompt", {
    sessionId = self.session.id,
    prompt = acp_prompt,
  }, function(result, err)
    if err then
      self.session.state = "ready"
      return actions.callback({ message = "Prompt failed", stderr = vim.json.encode(err) }, nil)
    end

    -- Prompt sent successfully - responses will come via notifications
    log:debug("Prompt sent to session: %s", self.session.id)
  end)
end

---Handle stdout data and route notifications
---@param data table
function Client:_handle_stdout(data)
  for _, chunk in ipairs(data) do
    if chunk == "" then
      goto continue
    end

    self.job.stdout = self.job.stdout .. chunk

    -- Process complete JSON lines
    while true do
      local newline_pos = self.job.stdout:find("\n")
      if not newline_pos then
        -- Check for complete JSON without newline at end of buffer
        local trimmed = self.job.stdout:match("^%s*(.-)%s*$")
        if trimmed ~= "" and (trimmed:match("^{.*}$") or trimmed:match("^%[.*%]$")) then
          local ok, msg = pcall(self.methods.decode, trimmed)
          if ok then
            self.job.stdout = ""
            self.methods.schedule(function()
              self:_handle_json_message(msg)
            end)
          end
        end
        break
      end

      local line = self.job.stdout:sub(1, newline_pos - 1)
      self.job.stdout = self.job.stdout:sub(newline_pos + 1)
      self:_process_line(line)
    end
    ::continue::
  end
end

---Process a complete JSON line
---@param line string
function Client:_process_line(line)
  if line == "" then
    return
  end

  local ok, msg = pcall(self.methods.decode, line)
  if ok then
    log:debug("Parsed message: %s", msg)
    self.methods.schedule(function()
      self:_handle_json_message(msg)
    end)
  else
    log:error("JSON parse error: %s", msg)
  end
end

---Handle parsed JSON messages (responses and notifications)
---@param msg table
function Client:_handle_json_message(msg)
  if msg.id then
    -- Handle response
    local cb = self.job.pending[msg.id]
    self.job.pending[msg.id] = nil

    if cb then
      if msg.error then
        cb(nil, msg.error)
      else
        cb(msg.result, nil)
      end
    end
  elseif msg.method then
    -- Handle notification
    self:_handle_notification(msg)
  end
end

---Handle ACP notifications
---@param msg table
function Client:_handle_notification(msg)
  local method = msg.method
  local params = msg.params

  if method == "session/update" then
    self:_handle_session_update(params)
  elseif method == "session/request_permission" then
    self:_handle_permission_request(msg.id, params)
  end
end

---Handle session update notifications (streaming content)
---@param params table
function Client:_handle_session_update(params)
  if not self.current_request then
    return
  end

  local session_update = params.sessionUpdate
  local content = params.content

  -- Process different types of session updates
  if session_update == "agentMessageChunk" and content and content.text then
    -- Stream content through adapter's chat_output handler
    local result = self.adapter.handlers.chat_output(self.adapter, params)
    if result then
      self.current_request.callback(nil, result, self.adapter)
    end
  elseif session_update == "agentMessageComplete" then
    -- Message complete - trigger done callback
    self.session.state = "ready"
    if self.current_request.done then
      self.current_request.done()
    end
    self.current_request = nil
  end
end

---Handle permission requests from agent
---@param id integer
---@param params table
function Client:_handle_permission_request(id, params)
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

  self:_rpc_response(id, {
    optionId = option_id,
  })
end

---Send JSON-RPC request with callback
---@param method string
---@param params table
---@param callback function
---@return integer|nil
function Client:_rpc_request(method, params, callback)
  if not self.job.handle then
    log:error("ACP client not running")
    if callback then
      callback(nil, { message = "Client not running" })
    end
    return nil
  end

  local id = self.job.next_id
  self.job.next_id = id + 1
  self.job.pending[id] = callback or function() end

  local req = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  local json_str = self.methods.encode(req) .. "\n"
  log:trace("Sending request: %s", json_str:gsub("\n", "\\n"))

  self.methods.chansend(self.job.handle, json_str)
  return id
end

---Send JSON-RPC response (for permission requests)
---@param id integer
---@param result table
function Client:_rpc_response(id, result)
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

---Cancel current request
function Client:_cancel_current_request()
  if self.current_request and self.session.id then
    self:_rpc_request("session/cancelled", { sessionId = self.session.id }, function() end)
    self.current_request = nil
    self.session.state = "ready"
  end
end

---Handle stderr data
---@param data table
function Client:_handle_stderr(data)
  for _, err in ipairs(data) do
    if err ~= "" then
      log:warn("ACP stderr (%s): %s", self.adapter.name, err)
    end
  end
end

---Handle process exit
---@param code integer
function Client:_handle_exit(code)
  log:debug("ACP client %s exited with code: %d", self.adapter.name, code)

  -- Fail all pending requests
  for _, cb in pairs(self.job.pending or {}) do
    if cb then
      self.methods.schedule(function()
        cb(nil, { message = "Process exited with code " .. code })
      end)
    end
  end

  -- Reset state
  self.job.pending = {}
  self.job.handle = nil
  self.session = { id = nil, state = "disconnected" }

  if self.adapter.handlers and self.adapter.handlers.on_exit then
    self.adapter.handlers.on_exit(self.adapter, code)
  end
end

---Check if the client is running
---@return boolean
function Client:is_running()
  return self.job.handle ~= nil
end

---Stop the ACP process
---@param client CodeCompanion.ACPClient
---@return boolean success
function Client.stop(client)
  if not client or not client.job or not client.job.handle then
    return false
  end

  -- Cancel current request
  client:_cancel_current_request()

  -- Cancel pending requests
  for _, cb in pairs(client.job.pending or {}) do
    if cb then
      client.methods.schedule(function()
        cb(nil, { message = "Connection closed" })
      end)
    end
  end
  client.job.pending = {}

  local success = client.methods.jobstop(client.job.handle) == 1
  client.job.handle = nil
  client.job.stdout = ""
  client.session = { id = nil, state = "disconnected" }

  if client.adapter.handlers and client.adapter.handlers.teardown then
    client.adapter.handlers.teardown(client.adapter)
  end

  return success
end

return Client
