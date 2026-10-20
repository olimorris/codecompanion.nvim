local config = require("codecompanion.config")
local markdown = require("codecompanion.utils.markdown")
local ui_utils = require("codecompanion.utils.ui")

local api = vim.api
local diff = vim.text.diff or vim.diff
local fmt = string.format

local CONSTANTS = {
  MAX_DETAIL_LENGTH = 100,
  NS_TOOL_CALLS = api.nvim_create_namespace("CodeCompanion-tool_calls"),
}

---@class CodeCompanion.Chat.UI.ToolCalls
local ToolCalls = {}

---Capitalise a tool kind ("edit" → "Edit", "switch_mode" → "Switch mode")
---@param kind string|nil
---@return string
local function format_kind(kind)
  if not kind or kind == "" then
    return "Tool"
  end
  local words = kind:gsub("_", " ")
  return words:sub(1, 1):upper() .. words:sub(2)
end

---Build the one-line summary of a tool call, shared so HTTP and ACP tool calls look the same
---@param opts { kind: string, detail?: string }
---@return string
function ToolCalls.format_summary(opts)
  local detail = vim.trim(((opts.detail or ""):gsub("%s+", " ")))
  detail = detail:gsub(vim.pesc(vim.fn.getcwd()) .. "/", "")

  if vim.fn.strchars(detail) > CONSTANTS.MAX_DETAIL_LENGTH then
    detail = vim.fn.strcharpart(detail, 0, CONSTANTS.MAX_DETAIL_LENGTH - 3) .. "..."
  end
  -- Escaping after truncating, so the cut can't separate a backslash from the character it escapes
  detail = markdown.escape_formatting(detail)

  if detail == "" then
    return fmt("**%s**", format_kind(opts.kind))
  end
  return fmt("**%s** %s", format_kind(opts.kind), detail)
end

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

---Write a tool call's summary line to the chat buffer, with its status icon
---@param chat CodeCompanion.Chat
---@param opts { summary: string, call_id?: string, status: string }
---@return number|nil line_number, number|nil icon_id
function ToolCalls.write(chat, opts)
  local line_number, icon_id = chat:add_buf_message({
    role = config.constants.LLM_ROLE,
    content = opts.summary,
  }, {
    status = opts.status,
    virt_text_pos = "inline",
    type = chat.MESSAGE_TYPES.TOOL_MESSAGE,
  })
  if line_number then
    ToolCalls.mark(chat, { line_number = line_number, call_id = opts.call_id })
  end
  return line_number, icon_id
end

---Rewrite a tool call's summary line with a new status
---@param chat CodeCompanion.Chat
---@param opts { line_number: number, summary: string, status: string, icon_id?: number }
---@return boolean updated, number|nil icon_id
function ToolCalls.update(chat, opts)
  return chat:update_buf_line({
    line_number = opts.line_number,
    content = opts.summary,
    status = opts.status,
    icon_id = opts.icon_id,
    priority = 120,
    virt_text_pos = "inline",
  })
end

---@param bufnr number
---@return nil
function ToolCalls.clear(bufnr)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_TOOL_CALLS, 0, -1)
end

---@param value any
---@return string
local function format_value(value)
  if type(value) == "table" then
    return vim.json.encode(value, { indent = "  " })
  end
  if value == vim.NIL then
    return "null"
  end
  return tostring(value)
end

---@param opts { lines: string[], value: any, ft?: string }
---@return nil
local function add_code_block(opts)
  local codeblock = markdown.form_codeblock(format_value(opts.value), { ft = opts.ft })
  vim.list_extend(opts.lines, vim.split(codeblock, "\n", { plain = true }))
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
    add_code_block({ lines = lines, value = arguments })
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
    add_code_block({ lines = lines, value = arguments[key] })
  end
  return lines
end

---@param opts { lines: string[], output: any, ft?: string }
---@return nil
local function add_output(opts)
  if opts.output == nil or opts.output == "" then
    return
  end
  vim.list_extend(opts.lines, { "", "---", "" })
  add_code_block({ lines = opts.lines, value = opts.output, ft = opts.ft })
end

---@param http_tool_call { call: table, output?: string }
---@return string[] lines, string title
local function format_http_call(http_tool_call)
  local call = http_tool_call.call
  local lines = format_arguments(call["function"].arguments)
  add_output({ lines = lines, output = http_tool_call.output })
  return lines, call["function"].name
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
---@return string|nil
local function get_acp_diff(call)
  local diffs = {}
  for _, block in ipairs(type(call.content) == "table" and call.content or {}) do
    if block.type == "diff" then
      -- A new file arrives with `oldText` as JSON null
      local old_text = type(block.oldText) == "string" and block.oldText .. "\n" or ""
      local new_text = type(block.newText) == "string" and block.newText .. "\n" or ""
      local hunks = diff(old_text, new_text, { result_type = "unified" })
      table.insert(diffs, fmt("--- %s\n+++ %s\n%s", block.path, block.path, hunks))
    end
  end

  return #diffs > 0 and table.concat(diffs, "\n") or nil
end

---@param call table
---@return string[] lines, string title
local function format_acp_call(call)
  local lines
  if type(call.rawInput) == "table" and not vim.tbl_isempty(call.rawInput) then
    lines = format_arguments(call.rawInput)
  else
    lines = { call.title and (call.title:gsub("\n", " ")) or "No arguments" }
    for _, location in ipairs(call.locations or {}) do
      if location.line then
        table.insert(lines, fmt("Location: %s:%d", location.path, location.line))
      else
        table.insert(lines, fmt("Location: %s", location.path))
      end
    end
  end

  local output = get_acp_output(call)
  if output then
    add_output({ lines = lines, output = output })
  else
    add_output({ lines = lines, output = get_acp_diff(call), ft = "diff" })
  end

  return lines, call.kind or "Tool Call"
end

---Open a float with the details of a tool call
---@param chat CodeCompanion.Chat
---@param opts { call_id: string }
---@return nil
function ToolCalls.open(chat, opts)
  local call_id = opts.call_id
  local lines, title
  local acp_call = chat.tool_calls.acp[call_id]
  if acp_call then
    lines, title = format_acp_call(acp_call)
  else
    local http_tool_call = chat.tool_calls.http[call_id]
    if not http_tool_call then
      return
    end
    lines, title = format_http_call(http_tool_call)
  end

  ui_utils.create_hover(lines, { title = title, focus_id = "codecompanion_tool_call" })
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

  ToolCalls.open(chat, { call_id = chat.tool_call_marks[marks[1][1]] })
end

return ToolCalls
