local ui_utils = require("codecompanion.utils.ui")

local api = vim.api
local fmt = string.format

local CONSTANTS = {
  NS_TOOL_CALLS = api.nvim_create_namespace("CodeCompanion-tool_calls"),
}

---@class CodeCompanion.Chat.UI.ToolCalls
local ToolCalls = {}

---Mark a tool call's summary line so its details can be opened from the cursor
---@param chat CodeCompanion.Chat
---@param opts { line_number: number, call_id: string }
---@return nil
function ToolCalls.mark(chat, opts)
  -- Without left gravity, ACP rewriting the line with a new status pushes the mark onto the next line
  local extmark_id = api.nvim_buf_set_extmark(chat.bufnr, CONSTANTS.NS_TOOL_CALLS, opts.line_number - 1, 0, {
    right_gravity = false,
  })
  chat.tool_call_marks[extmark_id] = opts.call_id
end

---@param bufnr number
---@return nil
function ToolCalls.clear(bufnr)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_TOOL_CALLS, 0, -1)
end

---@param opts { messages: CodeCompanion.Chat.Messages, call_id: string }
---@return table|nil
local function find_http_call(opts)
  for _, message in ipairs(opts.messages) do
    for _, call in ipairs(message.tools and message.tools.calls or {}) do
      if call.id == opts.call_id then
        return call
      end
    end
  end
end

---@param value any
---@return string[]
local function format_value(value)
  if type(value) == "table" then
    return vim.split(vim.json.encode(value, { indent = "  " }), "\n", { plain = true })
  end
  if value == vim.NIL then
    return { "null" }
  end
  return vim.split(tostring(value), "\n", { plain = true })
end

---@param lines string[]
---@param value any
---@return nil
local function add_code_block(lines, value)
  local value_lines = format_value(value)

  -- A value containing its own code fence would otherwise close the block early
  local longest_backticks = 2
  for _, line in ipairs(value_lines) do
    for backticks in line:gmatch("`+") do
      longest_backticks = math.max(longest_backticks, #backticks)
    end
  end
  local fence = string.rep("`", longest_backticks + 1)

  table.insert(lines, fence)
  vim.list_extend(lines, value_lines)
  table.insert(lines, fence)
end

---@param arguments string|table|nil
---@return string[]
local function format_arguments(arguments)
  if type(arguments) == "string" then
    local ok, decoded = pcall(vim.json.decode, arguments)
    arguments = ok and decoded or arguments
  end

  local is_empty_table = type(arguments) == "table" and vim.tbl_isempty(arguments)
  if arguments == nil or arguments == "" or arguments == vim.NIL or is_empty_table then
    return { "No arguments" }
  end

  local lines = {}
  if type(arguments) ~= "table" or vim.islist(arguments) then
    add_code_block(lines, arguments)
    return lines
  end

  local keys = vim.tbl_keys(arguments)
  table.sort(keys, function(a, b)
    if (a == "description") ~= (b == "description") then
      return a == "description"
    end
    return a < b
  end)
  for _, key in ipairs(keys) do
    if #lines > 0 then
      table.insert(lines, "")
    end
    table.insert(lines, fmt("**%s**", key))
    add_code_block(lines, arguments[key])
  end
  return lines
end

---@param lines string[]
---@param output any
---@return string[]
local function add_output(lines, output)
  if output == nil or output == "" then
    return lines
  end
  vim.list_extend(lines, { "", "---", "" })
  add_code_block(lines, output)
  return lines
end

---@param call table
---@param messages CodeCompanion.Chat.Messages
---@return string[] lines, string title
local function format_http_call(call, messages)
  local result = vim.iter(messages):find(function(message)
    return message.role == "tool" and message.tools and message.tools.call_id == call.id
  end)
  local lines = format_arguments(call["function"].arguments)
  return add_output(lines, result and result.content), call["function"].name
end

---@param call table
---@return string|nil
local function get_acp_output(call)
  if call.rawOutput ~= nil and call.rawOutput ~= vim.NIL then
    return call.rawOutput
  end

  local texts = {}
  for _, block in ipairs(type(call.content) == "table" and call.content or {}) do
    if block.type == "content" and block.content and block.content.type == "text" then
      table.insert(texts, block.content.text)
    end
  end
  return #texts > 0 and table.concat(texts, "\n") or nil
end

---@param call table
---@return string[] lines, string title
local function format_acp_call(call)
  local title = call.kind or "Tool Call"
  if type(call.rawInput) == "table" and not vim.tbl_isempty(call.rawInput) then
    return add_output(format_arguments(call.rawInput), get_acp_output(call)), title
  end

  local lines = { call.title and (call.title:gsub("\n", " ")) or "No arguments" }
  for _, location in ipairs(call.locations or {}) do
    if location.line then
      table.insert(lines, fmt("Location: %s:%d", location.path, location.line))
    else
      table.insert(lines, fmt("Location: %s", location.path))
    end
  end
  return add_output(lines, get_acp_output(call)), title
end

---Open a float with the details of the tool call on the cursor's line
---@param chat CodeCompanion.Chat
---@return nil
function ToolCalls.show(chat)
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local marks = api.nvim_buf_get_extmarks(chat.bufnr, CONSTANTS.NS_TOOL_CALLS, { row, 0 }, { row, -1 }, {})
  if #marks == 0 then
    return
  end

  local call_id = chat.tool_call_marks[marks[1][1]]

  local lines, title
  local acp_call = chat.acp_tool_calls[call_id]
  if acp_call then
    lines, title = format_acp_call(acp_call)
  else
    local http_call = find_http_call({ messages = chat.messages, call_id = call_id })
    if not http_call then
      return
    end
    lines, title = format_http_call(http_call, chat.messages)
  end

  ui_utils.create_hover(lines, { title = title, focus_id = "codecompanion_tool_call" })
end

return ToolCalls
