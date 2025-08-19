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

local TIMEOUTS = {
  DEFAULT = 2e4, -- 20 seconds
  RESPONSE_POLL = 10, -- 10ms
}

--=============================================================================
-- ACP Connection Class - Handles the connection to ACP agents
--=============================================================================

---@class CodeCompanion.ACPConnection
---@field adapter CodeCompanion.ACPAdapter
---@field adapter_modified CodeCompanion.ACPAdapter Modified adapter with environment variables set
---@field pending_responses table<integer, CodeCompanion.ACPConnection.PendingResponse>
---@field session_id string|nil
---@field _initialized boolean
---@field _authenticated boolean
---@field _active_prompt CodeCompanion.ACPPromptBuilder|nil
---@field _state {handle: table, next_id: integer, stdout_buffer: string}
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
    local initialized = self:_send_request("initialize", self.adapter_modified.parameters)
    if not initialized then
      log:error("[acp::connect] Failed to initialize")
      return nil
    end
    self._initialized = true
    log:debug("[acp::connect] ACP connection initialized")
  end

  if not self._authenticated then
    local authenticated = self:_send_request("authenticate", {
      methodId = self.adapter_modified.defaults.auth_method,
    })
    if not authenticated then
      log:error("[acp::connect] Failed to authenticate")
      return nil
    end
    self._authenticated = true
    log:debug("[acp::connect] Connection authenticated")
  end

  local new_session = self:_send_request("session/new", {
    cwd = vim.fn.getcwd(),
    mcpServers = self.adapter_modified.defaults.mcpServers or {},
  })

  if not new_session or not new_session.sessionId then
    log:error("[acp::connect] Failed to create session")
    return nil
  end

  self.session_id = new_session.sessionId
  log:debug("Created ACP session: %s", self.session_id)

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

---Wait for a specific response ID
---@param id integer
---@return nil
function Connection:_wait_for_response(id)
  local start_time = vim.uv.hrtime()
  local timeout = (self.adapter_modified.defaults.timeout or TIMEOUTS.DEFAULT) * 1e6

  while vim.uv.hrtime() - start_time < timeout do
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
  if not notification then
    log:debug("[acp::_process_notification] No notification provided")
    return self._active_prompt:_handle_done()
  end

  if notification.method == "session/update" then
    if self._active_prompt then
      self._active_prompt:_handle_session_update(notification.params.update)
    end
  elseif notification.method == "session/request_permission" then
    self:_handle_permission_request(notification.id, notification.params)
  elseif notification.method == "fs/read_text_file" then
    -- self:_handle_read_file_request(notification.id, notification.params)
  elseif notification.method == "fs/write_text_file" then
    -- self:_handle_write_file_request(notification.id, notification.params)
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

---Handle process exit
---@param code integer
---@param signal integer
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

---Handle permission request from agent
---@param id integer
---@param params table
function Connection:_handle_permission_request(id, params)
  local options = params.options
  local tool_call = params.toolCall

  local choices = {}
  local choices_map = {}
  local nvim_labels = {
    ["allow_always"] = "1 Allow always",
    ["allow_once"] = "2 Allow once",
    ["reject_once"] = "3 Reject",
    ["reject_always"] = "4 Reject always",
  }

  log:debug("[acp::_handle_permission_request] Tool: %s, Options: %s", tool_call.toolCallId, options)

  -- Format the options ready for the confirm dialog
  for i, option in ipairs(options) do
    table.insert(choices, "&" .. nvim_labels[option.kind])
    choices_map[i] = option.optionId
  end

  local choice_str = table.concat(choices, "\n")
  local choice = self.methods.confirm(
    string.format([[%s: %s ?]], util.capitalize(tool_call.kind), tool_call.title),
    choice_str,
    2, -- Default to allow once
    "Question"
  )

  if not id then
    return log:error("[acp::_handle_permission_request] No ID provided for permission response")
  end

  local response
  if choice > 0 and choices_map[choice] then
    response = {
      outcome = {
        outcome = "selected",
        optionId = choices_map[choice],
      },
    }
  else
    response = {
      outcome = {
        outcome = "canceled",
      },
    }
  end

  local response_msg = {
    jsonrpc = "2.0",
    id = id,
    result = response,
  }
  local json_str = self.methods.encode(response_msg) .. "\n"

  self:_write_to_process(json_str)
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
    id = self.connection._state.next_id,
    method = "session/prompt",
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
      self.handlers.message_chunk(params.content.text)
    end
  elseif params.sessionUpdate == "agent_thought_chunk" then
    if self.handlers.thought_chunk then
      self.handlers.thought_chunk(params.content.text)
    end
  elseif params.sessionUpdate == "tool_call" then
    log:trace("Tool call started: %s", params.toolCallId)
    if self.handlers.tool_call then
      self.handlers.tool_call(params)
    end
  elseif params.sessionUpdate == "tool_call_update" then
    log:trace("Tool call updated: %s (status: %s)", params.toolCallId, params.status)
    if self.handlers.tool_call then
      self.handlers.tool_call(params)
    end
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
      id = self.connection._state.next_id,
      method = "session/cancel",
      params = { sessionId = self.connection.session_id },
    }

    self.connection._state.next_id = self.connection._state.next_id + 1
    local json_str = self.connection.methods.encode(cancel_req) .. "\n"
    self.connection:_write_to_process(json_str)

    if self.options and not self.options.silent then
      self.options.status = "cancelled"
      util.fire("RequestFinished", self.options)
    end
  end

  self.connection._active_prompt = nil
end

return Connection
