--=============================================================================
-- PromptBuilder - Fluidly build the prompt which is sent to the agent
--=============================================================================
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

-- OpenCode can emit trailing prompt updates after end_turn.
local TURN_SETTLE_MS = 100

---@class CodeCompanion.ACP.PromptBuilder
---@field connection CodeCompanion.ACP.Connection
---@field messages table
---@field handlers table
---@field options table
---@field _sent boolean
---@field _done_pending boolean
---@field _done_reason string|nil
---@field _finished boolean
---@field _settle_generation number
local PromptBuilder = {}
PromptBuilder.__index = PromptBuilder

---Create new prompt builder
---@param connection CodeCompanion.ACP.Connection
---@param messages table
---@return CodeCompanion.ACP.PromptBuilder
function PromptBuilder.new(connection, messages)
  local self = setmetatable({
    connection = connection,
    handlers = {},
    messages = connection.adapter.handlers.form_messages(
      connection.adapter,
      messages,
      connection._agent_info.agentCapabilities
    ),
    options = {},
    _done_pending = false,
    _done_reason = nil,
    _finished = false,
    _sent = false,
    _settle_generation = 0,
  }, { __index = PromptBuilder }) ---@cast self CodeCompanion.ACP.PromptBuilder

  return self
end

---Handlers
function PromptBuilder:on_message_chunk(fn)
  self.handlers.message_chunk = fn
  return self
end
function PromptBuilder:on_thought_chunk(fn)
  self.handlers.thought_chunk = fn
  return self
end
function PromptBuilder:on_tool_call(fn)
  self.handlers.tool_call = fn
  return self
end
function PromptBuilder:on_tool_update(fn)
  self.handlers.tool_update = fn
  return self
end
function PromptBuilder:on_permission_request(fn)
  self.handlers.permission_request = fn
  return self
end
function PromptBuilder:on_write_text_file(fn)
  self.handlers.write_text_file = fn
  return self
end
function PromptBuilder:on_plan(fn)
  self.handlers.plan = fn
  return self
end
function PromptBuilder:on_complete(fn)
  self.handlers.complete = fn
  return self
end
function PromptBuilder:on_error(fn)
  self.handlers.error = fn
  return self
end
function PromptBuilder:on_cancel(fn)
  self.handlers.cancel = fn
  return self
end
function PromptBuilder:with_options(opts)
  self.options = vim.tbl_extend("force", self.options, opts or {})
  return self
end

local function resolve_status(stop_reason)
  if stop_reason == "refusal" then
    return "error"
  end
  if stop_reason == "max_tokens" then
    return "error"
  end
  if stop_reason == "max_turn_requests" then
    return "error"
  end
  if stop_reason == "canceled" then
    return "cancelled"
  end
  if stop_reason == "end_turn" or stop_reason == nil then
    return "success"
  end
  return tostring(stop_reason)
end

function PromptBuilder:clear_settle_timer()
  self._done_pending = false
  self._settle_generation = self._settle_generation + 1
end

function PromptBuilder:finish(stop_reason, status)
  if self._finished then
    return
  end

  self._finished = true
  self:clear_settle_timer()

  if status ~= "success" then
    log:warn("[acp::prompt_builder] Turn ended with stop_reason=%s", stop_reason or "unknown")
  end

  if self.handlers.complete then
    self.handlers.complete(stop_reason)
  end
  if self.options and not self.options.silent then
    self.options.status = status
    utils.fire("RequestFinished", self.options)
  end
  if self.connection._active_prompt == self then
    self.connection._active_prompt = nil
  end
end

function PromptBuilder:arm_settle_timer()
  self._settle_generation = self._settle_generation + 1
  local generation = self._settle_generation
  vim.defer_fn(function()
    if self._finished or not self._done_pending or generation ~= self._settle_generation then
      return
    end
    self:finish(self._done_reason, "success")
  end, TURN_SETTLE_MS)
end

---Send the prompt
---@return table job-like object for compatibility
function PromptBuilder:send()
  if self._sent then
    error("Prompt already sent")
  end
  self._sent = true
  self._finished = false
  self._done_pending = false
  self._done_reason = nil

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
      utils.fire("RequestStarted", self.options)
    end
  end

  -- Send the prompt
  local jsonrpc = require("codecompanion.utils.jsonrpc")
  local id = self.connection._state.id_gen:next()
  self._request_id = id
  local req = jsonrpc.request(id, self.connection.METHODS.SESSION_PROMPT, {
    sessionId = self.connection.session_id,
    prompt = self.messages,
  })
  self.connection:write_message(self.connection.methods.encode(req) .. "\n")

  self._streaming_started = false

  return {
    cancel = function()
      self:cancel()
    end,
  }
end

---Extract text from an ACP content block
---@param block table|nil
---@return string|nil
local function extract_text(block)
  if not block or type(block) ~= "table" then
    return nil
  end
  if block.type == "text" and type(block.text) == "string" then
    return block.text
  end
  if block.type == "resource_link" and type(block.uri) == "string" then
    return ("[resource: %s]"):format(block.uri)
  end
  if block.type == "resource" and block.resource then
    local r = block.resource
    if type(r.text) == "string" then
      return r.text
    end
    if type(r.uri) == "string" then
      return ("[resource: %s]"):format(r.uri)
    end
  end
  if block.type == "image" then
    return "[image]"
  end
  if block.type == "audio" then
    return "[audio]"
  end
  return nil
end

-- Export as static for reuse (e.g. session restore)
PromptBuilder.extract_text = extract_text

---Handle session update from the server
---@param params table
---@return nil
function PromptBuilder:handle_session_update(params)
  if self._done_pending then
    self:arm_settle_timer()
  end

  -- Fire streaming event on first chunk
  if self.options and not self._streaming_started then
    self._streaming_started = true
    if not self.options.silent then
      utils.fire("RequestStreaming", self.options)
    end
  end

  if params.sessionUpdate == "agent_message_chunk" then
    if self.handlers.message_chunk then
      local text = extract_text(params.content)
      if text and text ~= "" then
        self.handlers.message_chunk(text)
      end
    end
  elseif params.sessionUpdate == "agent_thought_chunk" then
    local text = extract_text(params.content)
    if text and text ~= "" and self.handlers.thought_chunk then
      self.handlers.thought_chunk(text)
    end
  elseif params.sessionUpdate == "plan" then
    if self.handlers.plan then
      self.handlers.plan(params.entries or {})
    end
  elseif params.sessionUpdate == "tool_call" then
    if self.handlers.tool_call then
      self.handlers.tool_call(params)
    end
  elseif params.sessionUpdate == "tool_call_update" then
    if self.handlers.tool_update then
      self.handlers.tool_update(params)
    end
  end
end

---Handle permission request from the agent
---@param id number
---@param params table
---@return nil
function PromptBuilder:handle_permission_request(id, params)
  if not id or not params then
    return
  end
  local tool_call = params.toolCall
  local options = params.options or {}

  local function respond(outcome)
    self.connection:send_result(id, { outcome = outcome })
  end

  local request = {
    id = id,
    session_id = params.sessionId,
    tool_call = tool_call,
    options = options,
    respond = function(option_id, cancelled)
      if cancelled or not option_id then
        respond({ outcome = "cancelled" })
      else
        respond({ outcome = "selected", optionId = option_id })
      end
    end,
  }

  if self.handlers.permission_request then
    self.handlers.permission_request(request)
  else
    request.respond(nil, true)
  end
end

---Handle errors from the agent
---@param error string|table The error message
function PromptBuilder:handle_error(error)
  if not error or self._finished then
    return
  end

  self._finished = true
  self:clear_settle_timer()

  local error_msg = type(error) == "string" and error or (error.message or "Unknown error")

  if self.handlers.error then
    self.handlers.error(error_msg)
  end

  if self.options and not self.options.silent then
    self.options.status = "error"
    self.options.error = error_msg
    utils.fire("RequestFinished", self.options)
  end

  if self.connection._active_prompt == self then
    self.connection._active_prompt = nil
  end
end

---Handle done event from the server
---@param stop_reason string
---@return nil
function PromptBuilder:handle_done(stop_reason)
  if self._finished then
    return
  end

  local status = resolve_status(stop_reason)
  if status == "success" and (stop_reason == "end_turn" or stop_reason == nil) then
    self._done_pending = true
    self._done_reason = stop_reason
    return self:arm_settle_timer()
  end

  self:finish(stop_reason, status)
end

---Cancel the prompt
---@return nil
function PromptBuilder:cancel()
  if self._finished then
    return
  end

  if self.connection.session_id then
    self.connection:send_notification(
      self.connection.METHODS.SESSION_CANCEL,
      { sessionId = self.connection.session_id }
    )
    if self.options and not self.options.silent then
      self.options.status = "cancelled"
      utils.fire("RequestFinished", self.options)
    end
  end

  -- Handler MUST respond to all requests with "cancelled"
  -- Ref: https://agentclientprotocol.com/protocol/prompt-turn#cancellation
  if self.handlers.cancel then
    pcall(self.handlers.cancel)
  end

  self._finished = true
  self:clear_settle_timer()
  if self.connection._active_prompt == self then
    self.connection._active_prompt = nil
  end
end

PromptBuilder.new = PromptBuilder.new
return PromptBuilder
