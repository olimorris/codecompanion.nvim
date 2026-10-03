local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")
local shared = require("codecompanion.adapters.shared")
local tokens = require("codecompanion.utils.tokens")

local fmt = string.format

local CONSTANTS = {
  MAX_CONTEXT_TOKENS = 16000,
  RESERVED_TOKENS = 3000,

  TOOL_DESCRIPTION = [[Edit the user's buffer by replacing an exact string with new text.

- `old_string` must match the buffer exactly, including whitespace and indentation
- The edit fails if `old_string` appears more than once in the code you can edit. Include more surrounding lines to make it unique, or set `replace_all` to change every occurrence
- Keep `old_string` short: usually 2-4 lines that uniquely identify the text to change
- To insert code, include the neighbouring lines in `old_string` and repeat them in `new_string` alongside the new code
- To delete text, set `new_string` to an empty string]],
}

local M = {}

---The `edit_file` schema, scoped to the one buffer that inline edits
---@return table
function M.get_tool_schema()
  local schema = vim.deepcopy(require("codecompanion.interactions.chat.tools.builtin.edit_file").schema)
  local tool = schema["function"]
  tool.description = CONSTANTS.TOOL_DESCRIPTION
  tool.parameters.properties.filepath = nil
  tool.parameters.required = vim.tbl_filter(function(name)
    return name ~= "filepath"
  end, tool.parameters.required)

  return schema
end

---@param lines string[]
---@param range { first: number, last: number }
---@return string
function M.get_text(lines, range)
  return table.concat(vim.list_slice(lines, range.first, range.last), "\n")
end

---Widen a range a line at a time, above and below, while the lines still fit within the token limit
---@param lines string[]
---@param opts { around: { first: number, last: number }, max_tokens: number }
---@return { first: number, last: number }
function M.get_lines_to_send(lines, opts)
  local first, last = opts.around.first, opts.around.last
  local used = tokens.calculate(M.get_text(lines, opts.around))

  local function try_line(index)
    local cost = tokens.calculate(lines[index])
    if used + cost > opts.max_tokens then
      return false
    end
    used = used + cost
    return true
  end

  local grew = true
  while grew do
    grew = false
    if first > 1 and try_line(first - 1) then
      first, grew = first - 1, true
    end
    if last < #lines and try_line(last + 1) then
      last, grew = last + 1, true
    end
  end

  return { first = first, last = last }
end

---@param adapter CodeCompanion.HTTPAdapter
---@return number
function M.get_max_tokens(adapter)
  local configured = config.interactions.inline.opts and config.interactions.inline.opts.max_context_tokens
  if configured then
    return configured
  end

  local input_limit = shared.input_limit(adapter)
  if not input_limit then
    return CONSTANTS.MAX_CONTEXT_TOKENS
  end

  return math.min(CONSTANTS.MAX_CONTEXT_TOKENS, input_limit - CONSTANTS.RESERVED_TOKENS)
end

---Join the reasoning from a response so it can be sent back alongside its tool calls
---@param adapter CodeCompanion.HTTPAdapter
---@param reasoning table
---@return string|table|nil
function M.join_reasoning(adapter, reasoning)
  if vim.tbl_isempty(reasoning) then
    return nil
  end

  if vim.iter(reasoning):any(function(item)
    return type(item) ~= "string"
  end) then
    return adapters.call_handler(adapter, "build_reasoning", { data = reasoning })
  end

  return table.concat(reasoning, "")
end

---@param tool_call table
---@return { args?: table, error?: string }
function M.decode_args(tool_call)
  local args = tool_call["function"] and tool_call["function"].arguments
  if type(args) == "string" then
    local ok, decoded = pcall(vim.json.decode, args ~= "" and args or "{}")
    if not ok then
      return { error = fmt("The arguments could not be decoded as JSON: %s", decoded) }
    end
    args = decoded
  end

  if type(args) ~= "table" then
    return { error = "The arguments must be a JSON object with `old_string`, `new_string` and `replace_all` keys" }
  end

  if type(args.old_string) ~= "string" or type(args.new_string) ~= "string" then
    local keys = vim.tbl_map(function(key)
      return fmt("`%s`", tostring(key):sub(1, 30))
    end, vim.tbl_keys(args))
    table.sort(keys)
    return {
      error = fmt(
        "`old_string` and `new_string` must both be strings, but the keys you sent were %s",
        table.concat(keys, ", ")
      ),
    }
  end

  return { args = args }
end

---The buffer's lines with the edited lines spliced back in
---@param target CodeCompanion.Inline.Target
---@return string[]
function M.get_new_content(target)
  local new_content = vim.list_slice(target.lines, 1, target.editable.first - 1)
  -- Splitting an empty string gives one blank line, which deleting the whole selection would leave behind
  if target.edited ~= "" then
    vim.list_extend(new_content, vim.split(target.edited, "\n", { plain = true }))
  end

  return vim.list_extend(new_content, vim.list_slice(target.lines, target.editable.last + 1))
end

return M
