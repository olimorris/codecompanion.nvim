--=============================================================================
-- PromptBuilder - Fluidly build the prompt which is sent to the agent
--=============================================================================
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

---@class CodeCompanion.ACP.PromptBuilder
---@field connection CodeCompanion.ACP.Connection
---@field messages table
---@field handlers table
---@field options table
---@field _sent boolean
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
    messages = connection.adapter.handlers.form_messages(connection.adapter, messages),
    options = {},
    _sent = false,
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
  local req = {
    jsonrpc = "2.0",
    id = self.connection._state.next_id,
    method = self.connection.METHODS.SESSION_PROMPT,
    params = { sessionId = self.connection.session_id, prompt = self.messages },
  }
  self.connection._state.next_id = self.connection._state.next_id + 1
  self.connection:_write_to_process(self.connection.methods.encode(req) .. "\n")

  self._streaming_started = false
  return {
    shutdown = function()
      self:cancel()
    end,
  }
end

---Extract renderable text from a content block
---@param block table|nil
---@return string|nil
function PromptBuilder:_extract_text(block)
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

---Handle session update from the server
---@param params table
---@return nil
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
      local text = self:_extract_text(params.content)
      if text and text ~= "" then
        self.handlers.message_chunk(text)
      end
    end
  elseif params.sessionUpdate == "agent_thought_chunk" then
    local text = self:_extract_text(params.content)
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
function PromptBuilder:_handle_permission_request(id, params)
  if not id or not params then
    return
  end
  local tool_call = params.toolCall
  local options = params.options or {}

  local function respond(outcome)
    self.connection:_send_result(id, { outcome = outcome })
  end

  local request = {
    id = id,
    session_id = params.sessionId,
    tool_call = tool_call,
    options = options,
    respond = function(option_id, canceled)
      if canceled or not option_id then
        respond({ outcome = "canceled" })
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

---Handle done event from the server
---@param stop_reason string
---@return nil
function PromptBuilder:_handle_done(stop_reason)
  local status = "success"
  if stop_reason == "refusal" then
    status = "error"
  elseif stop_reason == "max_tokens" then
    status = "error"
  elseif stop_reason == "max_turn_requests" then
    status = "error"
  elseif stop_reason == "canceled" then
    status = "cancelled"
  elseif stop_reason == "end_turn" or stop_reason == nil then
    status = "success"
  else
    status = tostring(stop_reason)
  end

  if status ~= "success" then
    log:warn("[acp::prompt_builder] Turn ended with stop_reason=%s", stop_reason or "unknown")
  end

  if self.handlers.complete then
    self.handlers.complete(stop_reason)
  end
  if self.options and not self.options.silent then
    self.options.status = status
    util.fire("RequestFinished", self.options)
  end
  self.connection._active_prompt = nil
end

---Cancel the prompt
---@return nil
function PromptBuilder:cancel()
  if self.connection.session_id then
    self.connection:_notify(self.connection.METHODS.SESSION_CANCEL, { sessionId = self.connection.session_id })
    if self.options and not self.options.silent then
      self.options.status = "cancelled"
      util.fire("RequestFinished", self.options)
    end
  end
  self.connection._active_prompt = nil
end

PromptBuilder.new = PromptBuilder.new
return PromptBuilder
