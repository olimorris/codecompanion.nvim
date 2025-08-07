--[[
==========================================================
    File:       codecompanion/acp.lua
    Author:     Oli Morris
----------------------------------------------------------
    Description:
      This module implements the ACP Connection for CodeCompanion.
      It provides a fluent API for interacting with ACP agents,
      handling session management, and processing responses.

      Inspired by Zed's ACP implementation patterns.
==========================================================
--]]

local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

---@class CodeCompanion.ACPConnection
---@field adapter CodeCompanion.ACPAdapter
---@field process {handle: table, next_id: integer, stdout_buffer: string}
---@field pending_responses table<integer, CodeCompanion.ACPConnection.PendingResponse>
---@field session_id string|nil
---@field _initialized boolean
---@field _authenticated boolean
---@field _active_prompt CodeCompanion.ACPPromptBuilder|nil
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
  confirm = { default = vim.fn.confirm },
  decode = { default = vim.json.decode },
  encode = { default = vim.json.encode },
  jobstart = { default = vim.system },
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

  return setmetatable({
    adapter = args.adapter,
    process = { handle = nil, next_id = 1, stdout_buffer = "" },
    pending_responses = {},
    session_id = args.session_id,
    methods = transform_static_methods(args.opts),
    _initialized = false,
    _authenticated = false,
  }, { __index = Connection })
end

---Connect to ACP process and establish session
---@return CodeCompanion.ACPConnection|nil self for chaining, nil on error
function Connection:connect()
  if not self.process.handle then
    if not self:_create_process() then
      return nil
    end
  end

  local adapter = self:_setup_adapter()

  -- Initialize if needed
  if not self._initialized then
    local initialized = self:_send_request("initialize", adapter.parameters)
    if not initialized then
      log:error("[acp::connect] Failed to initialize")
      return nil
    end
    self._initialized = true
    log:debug("ACP connection initialized")
  end

  -- Authenticate if needed
  if not self._authenticated then
    local authenticated = self:_send_request("authenticate", {
      methodId = adapter.defaults.auth_method,
    })
    if not authenticated then
      log:error("[acp::connect] Failed to authenticate")
      return nil
    end
    self._authenticated = true
    log:debug("ACP connection authenticated")
  end

  -- Always create new session
  -- NOTE: Check with the Zed team about this
  local new_session = self:_send_request("session/new", {
    cwd = vim.fn.getcwd(),
    mcpServers = adapter.defaults.mcpServers or {},
  })

  if not new_session or not new_session.sessionId then
    log:error("[acp::connect] Failed to create session")
    return nil
  end

  self.session_id = new_session.sessionId
  log:debug("Created ACP session: %s", self.session_id)

  return self
end

---Initiate a prompt
---@param messages table
---@return CodeCompanion.ACPPromptBuilder
function Connection:prompt(messages)
  if not self.session_id then
    return log:error("Connection not established. Call connect() first.")
  end
  return PromptBuilder.new(self, messages)
end

---Send a synchronous request and wait for response
---@param method string
---@param params table
---@return table|nil
function Connection:_send_request(method, params)
  if not self.process.handle then
    return nil
  end

  local id = self.process.next_id
  self.process.next_id = id + 1

  local request = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  local json = self.methods.encode(request) .. "\n"
  log:debug("Sending request: %s", method)

  if not self:_send_data(json) then
    return nil
  end

  -- Wait for response
  local start_time = vim.uv.hrtime()
  local timeout = (self.adapter.defaults.timeout or 2e4) * 1e6

  while true do
    -- NOTE: Leave this in, stuff gets messed up without it
    vim.wait(10)

    if self.pending_responses[id] then
      local result, err = unpack(self.pending_responses[id])
      self.pending_responses[id] = nil

      if err then
        log:error("[acp::_send_request] Error: %s", err)
        return nil
      end
      return result
    end

    local elapsed = vim.uv.hrtime() - start_time
    if elapsed > timeout then
      log:error("[acp::_send_request] Timeout for %s", method)
      return nil
    end
  end
end

---Create the ACP process
---@return boolean success
function Connection:_create_process()
  local adapter = self:_setup_adapter()

  log:debug("Starting ACP process: %s", adapter.command)

  if adapter.handlers and adapter.handlers.setup then
    if not adapter.handlers.setup(adapter) then
      log:error("[acp::_create_process] Setup failed")
      return false
    end
  end

  self.process.stdout_buffer = ""

  local ok, sysobj_or_err = pcall(
    self.methods.jobstart,
    adapter.command,
    {
      stdin = true,
      stdout = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::_create_process::stdout] Error: %s", err)
        elseif data then
          self:_handle_stdout(data)
        end
      end),
      stderr = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::_create_process::stderr] Error: %s", err)
        elseif data then
          self:_handle_stderr(data)
        end
      end),
      env = adapter.env_replaced or {},
      cwd = vim.fn.getcwd(),
    },
    self.methods.schedule_wrap(function(obj)
      self:_handle_exit(obj.code, obj.signal)
    end)
  )

  if not ok then
    log:error("[acp::_create_process] Failed: %s", sysobj_or_err)
    return false
  end

  self.process.handle = sysobj_or_err
  log:debug("ACP process started")
  return true
end

---Setup adapter with environment variables
---@return CodeCompanion.ACPAdapter
function Connection:_setup_adapter()
  local adapter = vim.deepcopy(self.adapter)
  adapter = adapter_utils.get_env_vars(adapter)
  adapter.parameters = adapter_utils.set_env_vars(adapter, adapter.parameters)
  adapter.defaults.auth_method = adapter_utils.set_env_vars(adapter, adapter.defaults.auth_method)
  adapter.defaults.mcpServers = adapter_utils.set_env_vars(adapter, adapter.defaults.mcpServers)
  adapter.command = adapter_utils.set_env_vars(adapter, adapter.command)
  return adapter
end

---Handle stdout data - JSON-RPC doesn't guarantee message boundaries align
---with I/O boundaries, so we need to buffer and handle this carefully.
---@param data string
function Connection:_handle_stdout(data)
  if not data or data == "" then
    return
  end

  log:debug("Received stdout: %s", data)
  self.process.stdout_buffer = self.process.stdout_buffer .. data

  -- Process complete JSON lines only
  while true do
    local newline_pos = self.process.stdout_buffer:find("\n")
    if not newline_pos then
      break
    end

    local line = self.process.stdout_buffer:sub(1, newline_pos - 1)
    self.process.stdout_buffer = self.process.stdout_buffer:sub(newline_pos + 1)

    line = vim.trim(line)
    if line ~= "" then
      self:_handle_message(line)
    end
  end
end

---Handle incoming JSON message
---@param line string
function Connection:_handle_message(line)
  local ok, message = pcall(self.methods.decode, line)
  if not ok then
    log:error("[acp::_handle_message] Invalid JSON: %s", line)
    return
  end

  log:debug("Processing message: %s", message)

  if message.id then
    self:_handle_response(message)

    if message.result == vim.NIL and self._active_prompt then
      self._active_prompt:_handle_done()
    end
  elseif message.method then
    self:_handle_notification(message)
  else
    log:error("Invalid message format")
  end

  if message.error then
    log:error("[acp::_handle_message] Error: %s", message.error)
  end
end

---Handle response to our request
---@param response table
function Connection:_handle_response(response)
  if response.error then
    self.pending_responses[response.id] = { nil, response.error }
    return
  end
  self.pending_responses[response.id] = { response.result, nil }
end

---Handle notification from server
---@param notification? table
function Connection:_handle_notification(notification)
  if not notification then
    return self._active_prompt:_handle_done()
  end

  if notification.method == "session/update" and self._active_prompt then
    self._active_prompt:_handle_session_update(notification.params)
  elseif notification.method == "session/request_permission" then
    self:_handle_permission_request(notification.id, notification.params)
  end
end

---Send data to process
---@param data string
---@return boolean
function Connection:_send_data(data)
  if not self.process.handle then
    log:error("Process not running")
    return false
  end

  local ok, err = pcall(function()
    self.process.handle:write(data)
  end)

  if not ok then
    log:error("Failed to send data: %s", err)
    return false
  end

  return true
end

---Handle stderr data
---@param data string
function Connection:_handle_stderr(data)
  if data and data ~= "" then
    for line in data:gmatch("[^\r\n]+") do
      if line ~= "" then
        log:debug("ACP stderr: %s", line)
      end
    end
  end
end

---Handle process exit
---@param code integer
---@param signal integer
function Connection:_handle_exit(code, signal)
  log:debug("ACP process exited: code=%d, signal=%d", code, signal or 0)

  self.process.handle = nil
  self.process.stdout_buffer = ""
  self._initialized = false
  self._authenticated = false

  if self.adapter.handlers and self.adapter.handlers.on_exit then
    self.adapter.handlers.on_exit(self.adapter, code)
  end
end

---Handle permission request from agent
---@param id integer
---@param params table
function Connection:_handle_permission_request(id, params)
  local tool_call = params.toolCall
  local options = params.options

  local choices = {}
  local option_map = {}

  for i, option in ipairs(options) do
    table.insert(choices, "&" .. option.name)
    option_map[i] = option.optionId
  end

  local choice_str = table.concat(choices, "\n")
  local choice = self.methods.confirm(string.format("Tool Permission:\n%s", tool_call.title), choice_str, 1, "Question")

  local response = {
    outcome = choice > 0 and {
      outcome = "selected",
      optionId = option_map[choice],
    } or {
      outcome = "cancelled",
    },
  }

  if id then
    local response_msg = {
      jsonrpc = "2.0",
      id = id,
      result = response,
    }
    local json_str = self.methods.encode(response_msg) .. "\n"
    self:_send_data(json_str)
  end
end

--=============================================================================
-- PromptBuilder - Fluent API for building prompts
--=============================================================================

---Create new prompt builder
---@param connection CodeCompanion.ACPConnection
---@param messages table
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder.new(connection, messages)
  return setmetatable({
    connection = connection,
    messages = connection.adapter.handlers.form_messages(connection.adapter, messages),
    handlers = {},
    options = {},
    _sent = false,
  }, { __index = PromptBuilder })
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

---Set handler for tool calls
---@param handler fun(tool_call: table)
---@return CodeCompanion.ACPPromptBuilder
function PromptBuilder:on_tool_call(handler)
  self.handlers.tool_call = handler
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
    id = self.connection.process.next_id,
    method = "session/prompt",
    params = {
      sessionId = self.connection.session_id,
      prompt = self.messages,
    },
  }

  self.connection.process.next_id = self.connection.process.next_id + 1
  local json_str = self.connection.methods.encode(prompt_req) .. "\n"

  self.connection:_send_data(json_str)
  self._streaming_started = false

  return {
    shutdown = function()
      self:cancel()
    end,
  }
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

  if params.sessionUpdate == "agentMessageChunk" then
    if self.handlers.message_chunk then
      self.handlers.message_chunk(params.content.text)
    end
  elseif params.sessionUpdate == "agentThoughtChunk" then
    if self.handlers.thought_chunk then
      self.handlers.thought_chunk(params.content.text)
    end
  elseif params.sessionUpdate == "toolCall" then
    if self.handlers.tool_call then
      self.handlers.tool_call(params)
    end
  end
end

---Handle done event from the server
---@return nil
function PromptBuilder:_handle_done()
  if self.handlers.complete then
    self.handlers.complete("completed")
  end

  -- Fire request finished event
  if self.options and not self.options.silent then
    self.options.status = "completed"
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
      id = self.connection.process.next_id,
      method = "session/cancelled",
      params = { sessionId = self.connection.session_id },
    }

    self.connection.process.next_id = self.connection.process.next_id + 1
    local json_str = self.connection.methods.encode(cancel_req) .. "\n"
    self.connection:_send_data(json_str)

    if self.options and not self.options.silent then
      self.options.status = "cancelled"
      util.fire("RequestFinished", self.options)
    end
  end

  self.connection._active_prompt = nil
end

return Connection
