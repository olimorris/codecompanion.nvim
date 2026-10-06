---@class CodeCompanion.Inline.HTTP
---@field adapter CodeCompanion.HTTPAdapter
---@field current_request? table
---@field inline CodeCompanion.Inline
---@field on_done fun(result: CodeCompanion.Inline.Result)
---@field retries number How many times a failed edit has been sent back to the LLM
---@field stopped? boolean
---@field streaming? boolean The adapter's stream setting before inline turned it off

local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local inline_prompt = require("codecompanion.interactions.inline.prompt")
local inline_utils = require("codecompanion.interactions.inline.utils")
local log = require("codecompanion.utils.log")
local replace = require("codecompanion.interactions.chat.tools.builtin.edit_file.replace")

local fmt = string.format

local CONSTANTS = {
  EDIT_RULE = "Make changes to the buffer by calling the `edit_file` tool, once per change",
  MAX_RETRIES = 1,
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",
}

---@class CodeCompanion.Inline.HTTP
local HTTP = {}

---@param args { inline: CodeCompanion.Inline }
---@return CodeCompanion.Inline.HTTP
function HTTP.new(args)
  return setmetatable({
    adapter = args.inline.adapter,
    inline = args.inline,
    retries = 0,
  }, { __index = HTTP })
end

---Send the messages with the inline `edit_file` tool, calling `on_done` once the edits are applied
---@param messages table
---@param opts { on_done: fun(result: CodeCompanion.Inline.Result) }
---@return nil
function HTTP:submit(messages, opts)
  self.on_done = opts.on_done
  self.streaming = self.adapter.opts.stream
  self.adapter.opts.stream = false

  table.insert(messages, 1, {
    role = config.constants.SYSTEM_ROLE,
    content = inline_prompt.build({
      filetype = self.inline.buffer_context.filetype,
      edit_rule = CONSTANTS.EDIT_RULE,
    }),
    _meta = { tag = "system_tag" },
    opts = { visible = false },
  })
  self:send(messages)
end

---@param messages table
---@return nil
function HTTP:send(messages)
  local adapter = self.adapter
  self.current_request = client.new({ adapter = adapter:map_schema_to_params() }):send(
    { messages = adapter:map_roles(vim.deepcopy(messages)), tools = { { edit_file = inline_utils.get_tool_schema() } } },
    {
      on_done = function(data)
        if self.stopped then
          return
        end
        self:done({ messages = messages, response = self:parse_response(data) })
      end,
      on_error = function(err)
        -- Cancelling the request makes curl report an error
        if self.stopped then
          return
        end
        self:finish({ error = fmt("Request failed with error %s", type(err) == "table" and err.message or err) })
      end,
      bufnr = self.inline.bufnr,
      buffer_context = self.inline.buffer_context or {},
      interaction = "inline",
    }
  )
end

---@return nil
function HTTP:stop()
  self.stopped = true
  if self.current_request then
    self.current_request.cancel()
    adapters.call_handler(self.adapter, "on_exit")
  end
  self:restore_stream()
end

---@return nil
function HTTP:restore_stream()
  self.adapter.opts.stream = self.streaming
  self.current_request = nil
end

---@param result CodeCompanion.Inline.Result
---@return nil
function HTTP:finish(result)
  self:restore_stream()
  self.on_done(result)
end

---@param data table
---@return { content: string, reasoning: table, tool_calls: table, error?: string }
function HTTP:parse_response(data)
  local response = { content = "", reasoning = {}, tool_calls = {} }

  local result = adapters.call_handler(self.adapter, "parse_chat", { data = data, tools = response.tool_calls })
  if result and result.extra and adapters.get_handler(self.adapter, "parse_meta") then
    result = adapters.call_handler(self.adapter, "parse_meta", { data = result })
  end
  if not result or result.status ~= CONSTANTS.STATUS_SUCCESS then
    response.error = result and result.output or "No response from the LLM"
    return response
  end

  response.content = vim.trim(result.output.content or "")
  if result.output.reasoning then
    table.insert(response.reasoning, result.output.reasoning)
  end
  return response
end

---Apply each tool call, in order, to the editable lines
---@param tool_calls table
---@return { tool_call: table, status: string, output: string }[]
function HTTP:apply_edits(tool_calls)
  local target = self.inline.target
  local results = {}

  for _, tool_call in ipairs(tool_calls) do
    local decoded = inline_utils.decode_args(tool_call)
    local edit = decoded.error and { error = decoded.error }
      or replace.apply(target.edited, {
        old_string = decoded.args.old_string,
        new_string = decoded.args.new_string,
        -- Weaker models send booleans as strings when the provider doesn't enforce the schema
        replace_all = decoded.args.replace_all == true or decoded.args.replace_all == "true",
      })

    if edit.error then
      table.insert(results, { tool_call = tool_call, status = CONSTANTS.STATUS_ERROR, output = edit.error })
    else
      target.edited = edit.content
      table.insert(results, { tool_call = tool_call, status = CONSTANTS.STATUS_SUCCESS, output = "Edit applied" })
    end
  end

  return results
end

---Apply the LLM's edits, sending any failures back to it once
---@param args { messages: table, response: table }
---@return nil
function HTTP:done(args)
  local response = args.response
  if response.error then
    return self:finish({ error = response.error })
  end

  if vim.tbl_isempty(response.tool_calls) then
    if response.content == "" then
      return self:finish({ error = fmt("%s returned no edits and no reply", self.adapter.formatted_name) })
    end
    return self:finish({ reply = response.content })
  end

  response.tool_calls = adapters.call_handler(self.adapter, "format_calls", { tools = response.tool_calls })
  local results = self:apply_edits(response.tool_calls)
  local failed = vim.tbl_filter(function(result)
    return result.status == CONSTANTS.STATUS_ERROR
  end, results)

  if vim.tbl_isempty(failed) then
    return self:finish({ lines = inline_utils.get_new_content(self.inline.target) })
  end

  if self.retries >= CONSTANTS.MAX_RETRIES then
    return self:finish({
      error = fmt("%s could not edit the buffer: %s", self.adapter.formatted_name, failed[1].output),
    })
  end

  self.retries = self.retries + 1
  log:debug("[Inline] Retrying after %d failed edit(s)", #failed)
  return self:send(self:add_tool_results(args.messages, { response = response, results = results }))
end

---Add the LLM's tool calls and their results to the messages, ready to send back
---@param messages table
---@param args { response: table, results: table }
---@return table
function HTTP:add_tool_results(messages, args)
  messages = vim.deepcopy(messages)

  table.insert(messages, {
    role = config.constants.LLM_ROLE,
    content = args.response.content,
    reasoning = inline_utils.join_reasoning(args.response.reasoning, { adapter = self.adapter }),
    tools = { calls = args.response.tool_calls },
    opts = { visible = false },
  })

  for _, result in ipairs(args.results) do
    local output = result.status == CONSTANTS.STATUS_ERROR and fmt("Edit failed: %s", result.output) or result.output
    local message = adapters.call_handler(self.adapter, "format_response", {
      tool_call = result.tool_call,
      output = output,
    })
    if message then
      table.insert(messages, message)
    end
  end

  return messages
end

return HTTP
