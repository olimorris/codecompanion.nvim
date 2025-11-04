--[[
===============================================================================
    File:       codecompanion/strategies/chat/acp/formatters.lua
    Description:
      Unified formatter for ACP tool calls.
      Handles all ACP agents (Claude Code, Codex, Gemini, etc) generically
      by trying multiple field structures and falling back to title parsing.
===============================================================================
--]]

local M = {}

---Get the relative path from a path
---@param p string
---@return string
local function relpath(p)
  return vim.fn.fnamemodify(p or "", ":.")
end

---Extract plain text from a ContentBlock
---@param block table|nil
---@return string|nil
function M.extract_text(block)
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

---Get the path to the diff
---@param tool_call table
---@return string|nil
local function diff_path(tool_call)
  if type(tool_call) ~= "table" or type(tool_call.content) ~= "table" then
    return nil
  end
  for _, c in ipairs(tool_call.content) do
    if c and c.type == "diff" and type(c.path) == "string" then
      return c.path
    end
  end
end

---Make the kind element of a tool call, pretty
---@param kind string|nil
---@return string
local function fmt_kind(kind)
  if not kind or kind == "" then
    return "Tool"
  end
  local s = kind:gsub("_", " ")
  s = s:sub(1, 1):upper() .. s:sub(2)
  return s
end

---Extract filename from a path (last component only)
---@param path string
---@return string
local function basename(path)
  if not path or path == "" then
    return ""
  end
  local name = path:match("([^/\\]+)$") or path
  return name
end

---Extract line range from rawInput for read operations
---@param raw_input table|nil
---@return string|nil
local function extract_line_range(raw_input)
  if type(raw_input) ~= "table" then
    return nil
  end

  local offset = tonumber(raw_input.offset)
  local limit = tonumber(raw_input.limit)
  if offset and limit then
    return ("L%d-%d"):format(offset + 1, offset + limit)
  elseif raw_input.line then
    return ("L%d"):format(tonumber(raw_input.line) or 0)
  end

  return nil
end

---Unescape common regex escape sequences for readability
---@param str string
---@return string
local function unescape_regex(str)
  str = str:gsub("\\%(", "("):gsub("\\%)", ")"):gsub("\\%{", "{"):gsub("\\%}", "}"):gsub("\\%.", "."):gsub('\\"', '"')
  return str
end

---Extract search pattern from rawInput, cleaning up complex patterns
---@param raw_input table|nil
---@param max_length number
---@return string|nil
local function extract_pattern(raw_input, max_length)
  if type(raw_input) ~= "table" then
    return nil
  end

  local pattern = raw_input.pattern
  if type(pattern) ~= "string" or pattern == "" then
    return nil
  end

  -- Remove markdown backticks
  pattern = pattern:gsub("`", "")

  pattern = unescape_regex(pattern)

  -- For glob patterns like **/file.lua, just show the filename
  if pattern:match("^%*%*/") then
    pattern = pattern:gsub("^%*%*/", "")
  end

  -- Trim long patterns
  if #pattern > max_length then
    pattern = pattern:sub(1, max_length - 3) .. "..."
  end

  return pattern
end

---Extract the target file path from locations array
---@param locations table|nil
---@return string|nil
local function extract_location_path(locations)
  if type(locations) ~= "table" or #locations == 0 then
    return nil
  end

  local first = locations[1]
  if type(first) == "table" and type(first.path) == "string" then
    return first.path
  end

  return nil
end

---Create a compact, sanitized title for a tool call
---Unified formatter handles all ACP agents by trying multiple field structures
---@param tool_call table
---@return string
function M.output_tool_call(tool_call)
  local kind = fmt_kind(tool_call.kind or "tool")
  local raw_input = tool_call.rawInput

  -- Handle diff operations separately
  local p = diff_path(tool_call)
  if p then
    return ("%s: %s"):format(kind, basename(relpath(p)))
  end

  -- Handle read operations with file paths
  if tool_call.kind == "read" and type(raw_input) == "table" then
    -- Try multiple locations for file path (works for Claude Code, Codex, and others)
    local file_path = raw_input.file_path
      or (raw_input.parsed_cmd and raw_input.parsed_cmd[1] and raw_input.parsed_cmd[1].path)
      or extract_location_path(tool_call.locations)

    if file_path then
      local range = extract_line_range(raw_input)
      local file = basename(relpath(file_path))
      if range then
        return ("%s: %s (%s)"):format(kind, file, range)
      end
      return ("%s: %s"):format(kind, file)
    end
  end

  -- Handle search/grep/execute operations
  if (tool_call.kind == "search" or tool_call.kind == "execute") and type(raw_input) == "table" then
    local pattern = extract_pattern(raw_input, 40)

    -- Also try to extract from parsed_cmd (Codex format)
    if not pattern and raw_input.parsed_cmd and raw_input.parsed_cmd[1] then
      local parsed = raw_input.parsed_cmd[1]
      pattern = parsed.query or parsed.pattern
    end

    if pattern then
      local path = raw_input.path or (raw_input.parsed_cmd and raw_input.parsed_cmd[1] and raw_input.parsed_cmd[1].path)

      if path and path ~= "" then
        -- If searching in a specific directory, show the dir name
        local dir = basename(path)
        if dir ~= "" then
          return ("%s: %s in %s"):format(kind, pattern, dir)
        end
      end
      return ("%s: %s"):format(kind, pattern)
    end
  end

  -- Fallback: use and sanitize the title field
  local t = tool_call.title or "Tool call"

  -- Handle incomplete/streaming tool calls
  if t == "undefined" or t:match("^%s*undefined%s*$") then
    return kind
  end

  -- Remove triple-backticks (markdown code fences) but keep single backticks
  t = t:gsub("```", "")

  -- Strip leading/trailing backticks but preserve them in the middle
  t = t:gsub("^`+", ""):gsub("`+$", "")

  -- Strip result preview indicators
  t = t:gsub("%s*=>.*$", "")
  t = t:gsub("%s*—.*$", "")

  -- For "Action target" format, prefer just the target
  local action, target = t:match("^%s*([^%s]+)%s+(.+)$")
  if action and target then
    target = target:gsub("^['\"]", ""):gsub("['\"]$", "")

    -- If target is a path, use basename
    if target:match("[/\\]") then
      target = basename(target)
    end

    -- Trim if needed
    if #target > 60 then
      target = target:sub(1, 57) .. "..."
    end

    return ("%s: %s"):format(kind, target)
  end

  -- Fallback: truncate and clean
  t = t:gsub("%s+$", "")
  if #t > 70 then
    t = t:sub(1, 67) .. "..."
  end

  return ("%s: %s"):format(kind, t)
end

---Strip markdown code block wrappers from content
---@param text string
---@return string
local function strip_code_blocks(text)
  -- Remove opening code fence with optional language
  text = text:gsub("^```%w*\n", "")
  -- Remove closing code fence
  text = text:gsub("\n```$", "")
  return text
end

---Check if content is likely a full file dump (too verbose for inline display)
---@param text string
---@param max_lines? number
---@return boolean
local function is_verbose_output(text, max_lines)
  max_lines = max_lines or 15
  local line_count = select(2, text:gsub("\n", "\n")) + 1
  return line_count > max_lines
end

---Create a summary for verbose content
---@param text string
---@param tool_call table
---@return string
local function summarize_verbose_content(text, tool_call)
  local lines = vim.split(text, "\n", { plain = true })
  local line_count = #lines

  -- Try to extract meaningful info from the tool call
  local kind = tool_call.kind
  local locations = tool_call.locations

  if kind == "read" and locations and #locations > 0 then
    local path = locations[1].path
    if path then
      return ("%d lines from %s"):format(line_count, basename(relpath(path)))
    end
  end

  if kind == "search" then
    local match_count = line_count
    return ("%d matches found"):format(match_count)
  end

  if kind == "execute" then
    return ("%d lines of output"):format(line_count)
  end

  return ("%d lines"):format(line_count)
end

---Summarize the content of a tool call
---@param tool_call table
---@return string|nil
function M.summarize_tool_content(tool_call)
  local contents = tool_call.content
  if type(contents) ~= "table" then
    return nil
  end
  for _, c in ipairs(contents) do
    if c.type == "diff" then
      local path = c.path and relpath(c.path) or "file"
      local old_lines = vim.split(c.oldText or "", "\n", { plain = true })
      local new_lines = vim.split(c.newText or "", "\n", { plain = true })
      local delta = #new_lines - #old_lines
      if delta > 0 then
        return ("Edited %s (+%d lines)"):format(path, delta)
      elseif delta < 0 then
        return ("Edited %s (-%d lines)"):format(path, math.abs(delta))
      else
        return ("Edited %s"):format(path)
      end
    elseif c.type == "content" then
      local t = M.extract_text(c.content)
      if t and t ~= "" then
        -- Strip markdown code blocks
        t = strip_code_blocks(t)

        -- If content is too verbose, summarize it
        if is_verbose_output(t) then
          return summarize_verbose_content(t, tool_call)
        end

        return t
      end
    end
  end
  return nil
end

---Create a one-line message for tool-call events
---@param tool_call table
---@param adapter CodeCompanion.ACPAdapter
---@return string
function M.tool_message(tool_call, adapter)
  local status = tool_call.status or "pending"
  local title = M.output_tool_call(tool_call)
  local trim_tool_output = adapter.opts and adapter.opts.trim_tool_output

  if status == "completed" then
    local summary
    if trim_tool_output then
      summary = title
    else
      summary = M.summarize_tool_content(tool_call)
    end
    return summary or (title .. " — completed")
  elseif status == "in_progress" then
    return title .. " — running"
  elseif status == "failed" then
    local summary
    if trim_tool_output then
      summary = title
    else
      summary = M.summarize_tool_content(tool_call)
    end
    return summary or (title .. " — failed")
  else
    return title
  end
end

---Create a one-line message for file-write
---@param info table
---@return string
function M.fs_write_message(info)
  local path = relpath(info.path or "")
  local bytes = tonumber(info.bytes or 0) or 0
  return ("Wrote %d bytes to %s"):format(bytes, path ~= "" and path or "file")
end

return M
