local log = require("codecompanion.utils.log")

---@class CodeCompanion.CLIClient
---@field name string
---@field command table
---@field opts table
---@field protocol string
---@field parameters table
---@field job_handle integer|nil
---@field stdout_buffer string
---@field next_id integer
---@field pending table
---@field static table
local Client = {}
Client.static = {}

-- Static options for easier testing/mocking
Client.static.opts = {
  jobstart = { default = vim.fn.jobstart },
  chansend = { default = vim.fn.chansend },
  jobstop = { default = vim.fn.jobstop },
  schedule = { default = vim.schedule },
  encode = { default = vim.json.encode },
  decode = { default = vim.json.decode },
}

local function transform_static(opts)
  local ret = {}
  for k, v in pairs(Client.static.opts) do
    if opts and opts[k] ~= nil then
      ret[k] = opts[k]
    else
      ret[k] = v.default
    end
  end
  return ret
end

---@class CodeCompanion.CliClientArgs
---@field name string
---@field command table
---@field protocol string
---@field parameters table
---@field opts table|nil
---@field handlers table|nil

---@param args CodeCompanion.CliClientArgs
---@return CodeCompanion.CLIClient
function Client.new(args)
  args = args or {}

  return setmetatable({
    name = args.name or "cli_client",
    command = args.command or {},
    protocol = args.protocol or "jsonrpc",
    parameters = args.parameters or {},
    opts = vim.tbl_extend("force", {
      env = {},
      timeout = 30000,
      auto_initialize = true,
    }, args.opts or {}),
    handlers = args.handlers or {},
    job_handle = nil,
    stdout_buffer = "",
    next_id = 1,
    pending = {},
    static = transform_static(args.opts and args.opts.static),
  }, { __index = Client })
end

---Start the CLI process
---@return boolean success
function Client:start()
  if self.job_handle then
    log:warn("CLI client %s already running", self.name)
    return false
  end

  -- Run setup handler if present
  if self.handlers.setup and not self.handlers.setup(self) then
    return false
  end

  log:info("Starting CLI client: %s", self.name)

  local job_opts = {
    stdin = "pipe",
    stdout = "pipe",
    stderr = "pipe",
    env = self.job_env or self.opts.env,
    on_stdout = function(_, data, _)
      self:_handle_stdout(data)
    end,
    on_stderr = function(_, data, _)
      self:_handle_stderr(data)
    end,
    on_exit = function(_, code, _)
      self:_handle_exit(code)
    end,
    stdout_buffered = false,
    stderr_buffered = false,
  }

  self.job_handle = self.static.jobstart(self.command, job_opts)

  if self.job_handle <= 0 then
    log:error("Failed to start CLI client: %s", self.name)
    self.job_handle = nil
    return false
  end

  log:debug("CLI client %s started with job handle: %d", self.name, self.job_handle)

  -- Auto-initialize if configured
  if self.opts.auto_initialize then
    vim.defer_fn(function()
      self:initialize()
    end, 100)
  end

  return true
end

---Stop the CLI process
---@return boolean success
function Client:stop()
  if not self.job_handle then
    return true
  end

  log:info("Stopping CLI client: %s", self.name)

  -- Cancel all pending requests
  for id, cb in pairs(self.pending) do
    if cb then
      self.static.schedule(function()
        cb(nil, { error = { message = "Connection closed" } })
      end)
    end
  end
  self.pending = {}

  local success = self.static.jobstop(self.job_handle) == 1
  self.job_handle = nil
  self.stdout_buffer = ""

  if self.handlers.teardown then
    self.handlers.teardown(self)
  end

  return success
end

---Check if the client is running
---@return boolean
function Client:is_running()
  return self.job_handle ~= nil
end

---Initialize the connection
---@param callback? function
function Client:initialize(callback)
  if self.protocol == "acp" then
    self:request("initialize", self.parameters, function(result, err)
      if err then
        log:error("%s initialization failed: %s", self.name, vim.inspect(err))
        if callback then
          callback(false, err)
        end
        return
      end

      log:info("%s initialized successfully", self.name)
      if result.serverInfo then
        log:debug("Server: %s v%s", result.serverInfo.name, result.serverInfo.version)
      end

      if callback then
        callback(true, result)
      end
    end)
  else
    if callback then
      callback(true)
    end
  end
end

---Send an RPC request
---@param method string
---@param params table
---@param callback function
---@return integer|nil request_id
function Client:request(method, params, callback)
  if not self.job_handle then
    log:error("CLI client %s not running", self.name)
    if callback then
      callback(nil, { error = { message = "Client not running" } })
    end
    return nil
  end

  local id = self.next_id
  self.next_id = id + 1
  self.pending[id] = callback or function() end

  local req = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  local json_str = self.static.encode(req) .. "\n"
  log:trace("Sending request: %s", json_str:gsub("\n", "\\n"))

  self.static.chansend(self.job_handle, json_str)

  -- Set up timeout
  if self.opts.timeout > 0 then
    vim.defer_fn(function()
      if self.pending[id] then
        local cb = self.pending[id]
        self.pending[id] = nil
        cb(nil, { error = { message = "Request timeout" } })
      end
    end, self.opts.timeout)
  end

  return id
end

---Create a new session (ACP protocol)
---@param opts table
---@param callback function
function Client:new_session(opts, callback)
  if self.protocol ~= "acp" then
    callback(nil, { error = { message = "new_session requires ACP protocol" } })
    return
  end

  local args = {
    mcpServers = opts.mcpServers or {},
    clientTools = {
      requestPermission = vim.NIL,
      writeTextFile = vim.NIL,
      readTextFile = vim.NIL,
    },
    cwd = opts.cwd or ".",
  }

  self:request("tools/call", {
    name = "acp/new_session",
    arguments = args,
  }, function(result, err)
    if err then
      callback(nil, err)
      return
    end

    local session_id = result.structuredContent and result.structuredContent.sessionId
    if not session_id then
      callback(nil, { error = { message = "No session ID in response" } })
      return
    end

    log:info("Created ACP session: %s", session_id)
    callback(session_id, nil)
  end)
end

---Send a prompt to an ACP session
---@param session_id string
---@param messages table
---@param callback function
function Client:prompt(session_id, messages, callback)
  if self.protocol ~= "acp" then
    callback(nil, { error = { message = "prompt requires ACP protocol" } })
    return
  end

  -- Convert CodeCompanion messages to ACP format
  local prompt = {}
  for _, msg in ipairs(messages) do
    if msg.content and msg.content ~= "" then
      table.insert(prompt, {
        type = "text",
        text = msg.content,
      })
    end
  end

  self:request("tools/call", {
    name = "acp/prompt",
    arguments = {
      sessionId = session_id,
      prompt = prompt,
    },
  }, function(result, err)
    if err then
      callback(nil, err)
      return
    end

    -- Extract response content
    local content = ""
    if result.content and #result.content > 0 then
      for _, item in ipairs(result.content) do
        if item.text then
          content = content .. item.text
        end
      end
    end

    callback({
      status = "success",
      output = {
        role = "assistant",
        content = content,
      },
    }, nil)
  end)
end

---Handle stdout data
---@param data table
function Client:_handle_stdout(data)
  log:trace("Raw stdout: %s", vim.inspect(data))

  for _, chunk in ipairs(data) do
    if chunk == "" then
      goto continue
    end

    self.stdout_buffer = self.stdout_buffer .. chunk

    -- Process complete JSON lines
    while true do
      local newline_pos = self.stdout_buffer:find("\n")
      if not newline_pos then
        -- Check for complete JSON without newline
        if self.stdout_buffer:match("^%s*{.*}%s*$") then
          local line = self.stdout_buffer:match("^%s*(.-)%s*$")
          self.stdout_buffer = ""
          self:_process_json_line(line)
        end
        break
      end

      local line = self.stdout_buffer:sub(1, newline_pos - 1)
      self.stdout_buffer = self.stdout_buffer:sub(newline_pos + 1)
      self:_process_json_line(line)
    end
    ::continue::
  end
end

---Process a JSON line
---@param line string
function Client:_process_json_line(line)
  if line == "" then
    return
  end

  local ok, msg = pcall(self.static.decode, line)
  if not ok then
    log:error("JSON parse error: %s", msg)
    return
  end

  log:trace("Parsed message: %s", vim.inspect(msg))

  self.static.schedule(function()
    self:_handle_message(msg)
  end)
end

---Handle a parsed RPC message
---@param msg table
function Client:_handle_message(msg)
  if msg.method then
    -- Handle notification
    if msg.method == "acp/session_update" and self.handlers.session_update then
      self.handlers.session_update(self, msg.params)
    elseif self.handlers.notification then
      self.handlers.notification(self, msg.method, msg.params)
    end
  elseif msg.id then
    -- Handle response
    local cb = self.pending[msg.id]
    self.pending[msg.id] = nil

    if cb then
      if msg.error then
        cb(nil, msg.error)
      else
        cb(msg.result, nil)
      end
    end
  end
end

---Handle stderr data
---@param data table
function Client:_handle_stderr(data)
  for _, err in ipairs(data) do
    if err ~= "" then
      log:warn("CLI stderr (%s): %s", self.name, err)
    end
  end
end

---Handle process exit
---@param code integer
function Client:_handle_exit(code)
  log:info("CLI client %s exited with code: %d", self.name, code)

  -- Fail all pending requests
  for id, cb in pairs(self.pending) do
    if cb then
      self.static.schedule(function()
        cb(nil, { error = { message = "Process exited with code " .. code } })
      end)
    end
  end

  self.pending = {}
  self.job_handle = nil

  if self.handlers.on_exit then
    self.handlers.on_exit(self, code)
  end
end

return Client
