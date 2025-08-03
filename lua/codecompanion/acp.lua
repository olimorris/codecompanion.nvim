local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.ACPClient
---@field adapter CodeCompanion.ACPAdapter The ACP adapter used by the client
---@field job {handle: integer, next_id: integer, pending: table, stdout: string}|nil The job handle for the ACP process
---@field opts nil|table
---@field methods table

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
---@return CodeCompanion.ACPClient
function Client.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    job = {},
    methods = transform_static_methods(args.opts),
    opts = args.opts or {},
  }, { __index = Client })
end

---Start the ACP process
---@return CodeCompanion.ACPClient
function Client:start()
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
    log:error("Failed to start ACP client: %s", adapter.name)
    return self
  end

  log:debug("ACP process started with job handle: %d", self.job.handle)

  return self
end

-------------------------------------------------------------------------------
-- Handle stdout data
-------------------------------------------------------------------------------

---Handle stdout data
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
          -- Try to parse as complete JSON
          local ok, msg = pcall(self.methods.decode, trimmed)
          if ok then
            self.job.stdout = ""
            log:debug("Parsed message: %s", msg)
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

-- Extract line processing to separate method
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

-- Extract message handling to separate method
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
    -- Handle notification (for future use)
  end
end

-------------------------------------------------------------------------------
-- Handle the stderr and exit events
-------------------------------------------------------------------------------

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
        cb(nil, { error = { message = "Process exited with code " .. code } })
      end)
    end
  end

  self.job.pending = {}
  self.job.handle = nil

  if self.adapter.handlers and self.adapter.handlers.on_exit then
    self.adapter.handlers.on_exit(self.adapter, code)
  end
end

---Send a JSON-RPC request
---@param method string
---@param params table
---@param callback function
---@return integer|nil request_id
function Client:request(method, params, callback)
  if not self.job.handle then
    log:error("ACP client not running")
    if callback then
      callback(nil, { error = { message = "Client not running" } })
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

---Send a JSON-RPC notification (no response expected)
---@param method string
---@param params table
function Client:notify(method, params)
  if not self.job.handle then
    log:error("ACP client not running")
    return
  end

  local notification = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }

  local json_str = self.methods.encode(notification) .. "\n"
  log:trace("Sending notification: %s", json_str:gsub("\n", "\\n"))

  self.methods.chansend(self.job.handle, json_str)
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

  -- Cancel pending requests
  for _, cb in pairs(client.job.pending or {}) do
    if cb then
      client.methods.schedule(function()
        cb(nil, { error = { message = "Connection closed" } })
      end)
    end
  end
  client.job.pending = {}

  local success = client.methods.jobstop(client.job.handle) == 1
  client.job.handle = nil
  client.job.stdout = ""

  if client.adapter.handlers and client.adapter.handlers.teardown then
    client.adapter.handlers.teardown(client.adapter)
  end

  return success
end

return Client
