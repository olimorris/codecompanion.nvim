---@class CodeCompanion.Inline.HTTP
---@field adapter CodeCompanion.HTTPAdapter
---@field current_request? table
---@field edited string The editable lines with every successful edit applied
---@field inline CodeCompanion.Inline
---@field on_done fun(result: CodeCompanion.Inline.Result)
---@field retries number How many times a failed edit has been sent back to the LLM
---@field stopped? boolean

local Rules = require("codecompanion.interactions.shared.rules")
local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local inline_prompt = require("codecompanion.interactions.inline.prompt")
local inline_utils = require("codecompanion.interactions.inline.utils")
local log = require("codecompanion.utils.log")
local replace = require("codecompanion.interactions.chat.tools.builtin.edit_file.replace")
local skills = require("codecompanion.skills")

local fmt = string.format

local CONSTANTS = {
  EDIT_RULE = "Make changes to the buffer by calling the `edit_file` tool, once per change",
  MAX_RETRIES = 1,
}

---@class CodeCompanion.Inline.HTTP
local HTTP = {}

---@param args { inline: CodeCompanion.Inline }
---@return CodeCompanion.Inline.HTTP
function HTTP.new(args)
  local target = args.inline.target
  return setmetatable({
    adapter = args.inline.adapter,
    edited = inline_utils.get_text(target.lines, target.editable),
    inline = args.inline,
    retries = 0,
  }, { __index = HTTP })
end

---Send the messages with the system prompt, rules, skills and the `edit_file` tool, applying the edits
---@param messages table
---@param opts { on_done: fun(result: CodeCompanion.Inline.Result) }
---@return nil
function HTTP:submit(messages, opts)
  self.on_done = opts.on_done

  local preamble = {
    {
      role = config.constants.SYSTEM_ROLE,
      content = inline_prompt.build({
        filetype = self.inline.buffer_context.filetype,
        edit_rule = CONSTANTS.EDIT_RULE,
      }),
      _meta = { tag = "system_tag" },
      opts = { visible = false },
    },
  }
  vim.list_extend(preamble, Rules.get_messages(config.rules.opts.inline.autoload))
  vim.list_extend(preamble, skills.get_messages(config.skills.opts.inline.autoload))
  self:send(vim.list_extend(preamble, messages))
end

---@param messages table
---@return nil
function HTTP:send(messages)
  local adapter = self.adapter
  local response = { content = "", reasoning = {}, tool_calls = {} }

  self.current_request = client.new({ adapter = adapter:map_schema_to_params() }):send(
    { messages = adapter:map_roles(vim.deepcopy(messages)), tools = { { edit_file = inline_utils.get_tool_schema() } } },
    {
      on_chunk = function(data)
        self:parse_chunk(data, response)
      end,
      on_done = function(data)
        if self.stopped then
          return
        end
        if data then
          self:parse_chunk(data, response)
        end
        response.content = vim.trim(response.content)
        self:done({ messages = messages, response = response })
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
  self.current_request = nil
end

---@param result CodeCompanion.Inline.Result
---@return nil
function HTTP:finish(result)
  self.current_request = nil
  self.on_done(result)
end

---Add a streamed chunk, or the whole non-streamed response, to the response
---@param data table
---@param response { content: string, reasoning: table, tool_calls: table, error?: string }
---@return nil
function HTTP:parse_chunk(data, response)
  local result = adapters.call_handler(self.adapter, "parse_chat", { data = data, tools = response.tool_calls })
  if result and result.extra and adapters.get_handler(self.adapter, "parse_meta") then
    result = adapters.call_handler(self.adapter, "parse_meta", { data = result })
  end
  if not result then
    return
  end
  if result.status ~= "success" then
    response.error = response.error or result.output
    return
  end

  response.content = response.content .. (result.output.content or "")
  if result.output.reasoning then
    table.insert(response.reasoning, result.output.reasoning)
  end
end

---Apply each tool call, in order, to the editable lines
---@param tool_calls table
---@return { tool_call: table, error?: string }[]
function HTTP:apply_edits(tool_calls)
  local results = {}

  for _, tool_call in ipairs(tool_calls) do
    local decoded = inline_utils.decode_args(tool_call)
    local edit = decoded.error and { error = decoded.error }
      or replace.apply(self.edited, {
        old_string = decoded.args.old_string,
        new_string = decoded.args.new_string,
        -- Weaker models send booleans as strings when the provider doesn't enforce the schema
        replace_all = decoded.args.replace_all == true or decoded.args.replace_all == "true",
      })

    self.edited = edit.content or self.edited
    table.insert(results, { tool_call = tool_call, error = edit.error })
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
    return result.error ~= nil
  end, results)

  if vim.tbl_isempty(failed) then
    return self:finish({ lines = self:get_new_content() })
  end

  if self.retries >= CONSTANTS.MAX_RETRIES then
    return self:finish({
      error = fmt("%s could not edit the buffer: %s", self.adapter.formatted_name, failed[1].error),
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
    local message = adapters.call_handler(self.adapter, "format_response", {
      tool_call = result.tool_call,
      output = result.error and fmt("Edit failed: %s", result.error) or "Edit applied",
    })
    if message then
      table.insert(messages, message)
    end
  end

  return messages
end

---The buffer's lines with the edited lines spliced back in
---@return string[]
function HTTP:get_new_content()
  local target = self.inline.target
  local new_content = vim.list_slice(target.lines, 1, target.editable.first - 1)
  -- Splitting an empty string gives one blank line, which deleting the whole selection would leave behind
  if self.edited ~= "" then
    vim.list_extend(new_content, vim.split(self.edited, "\n", { plain = true }))
  end

  return vim.list_extend(new_content, vim.list_slice(target.lines, target.editable.last + 1))
end

return HTTP
