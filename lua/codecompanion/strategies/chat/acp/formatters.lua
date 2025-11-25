--[[
===============================================================================
    File:       codecompanion/strategies/chat/acp/formatters.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      This module provides universal formatting for ACP tool calls across different agents.
      It handles inconsistencies in JSON RPC output and ensures:
      - Single-line output (no triple backticks or newlines)
      - Consistent status formatting
      - Smart content summarization
      - Proper path handling
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local M = {}

---Get the relative path from a path
---@param p string
---@return string
local function relpath(p)
  return vim.fn.fnamemodify(p or "", ":.")
end

---Sanitize text content for single-line display
---@param text string
---@param max_length? number Maximum length before truncation (default: 100)
---@return string
local function sanitize_text(text, max_length)
  if not text or text == "" then
    return ""
  end

  max_length = max_length or 100

  -- Remove triple backticks and code block markers
  text = text:gsub("```[%w]*\n?", "")
  text = text:gsub("```", "")

  -- Replace newlines with spaces and collapse multiple spaces
  text = text:gsub("\r?\n", " ")
  text = text:gsub("%s+", " ")

  -- Trim whitespace
  text = text:match("^%s*(.-)%s*$") or ""

  -- Truncate if too long
  if #text > max_length then
    text = text:sub(1, max_length - 3) .. "..."
  end

  return text
end

---Extract plain text from a ContentBlock
---@param block table|nil
---@return string|nil
function M.extract_text(block)
  if not block or type(block) ~= "table" then
    return nil
  end
  if block.type == "text" and type(block.text) == "string" then
    return sanitize_text(block.text)
  end
  if block.type == "resource_link" and type(block.uri) == "string" then
    return ("[resource: %s]"):format(block.uri)
  end
  if block.type == "resource" and block.resource then
    local r = block.resource
    if type(r.text) == "string" then
      return sanitize_text(r.text)
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

---Extract meaningful command or operation from title
---@param title string
---@return string
local function extract_operation(title)
  if not title or title == "" then
    return "Tool call"
  end

  -- Remove common prefixes and clean up
  title = title:gsub("^%s*", "") -- trim leading whitespace

  -- Handle backtick-wrapped commands (e.g., "`ls -la`")
  local backtick_cmd = title:match("^`([^`]+)`")
  if backtick_cmd then
    return backtick_cmd
  end

  -- Handle quoted commands (e.g., "Sheffield United")
  local quoted = title:match('^"([^"]+)"')
  if quoted then
    return quoted
  end

  -- Strip " => …" preview and similar patterns
  title = title:gsub("%s*=>.*$", "")
  title = title:gsub("%s*—.*$", "")

  -- If "name: something", keep the full thing if it looks like a URL
  -- Otherwise, for short prefixes, keep just the prefix
  local before_colon = title:match("^%s*([^:]+)%s*:")
  if before_colon and #before_colon < 40 then
    -- Don't strip if the part after colon looks like a URL
    local after_colon = title:match("^%s*[^:]+%s*:%s*(.+)")
    if not (after_colon and (after_colon:match("^//") or after_colon:match("^https?://"))) then
      title = before_colon
    end
  end

  -- Clean up trailing whitespace
  title = title:gsub("%s+$", "")

  return title ~= "" and title or "Tool call"
end

---Short, sanitized title for a tool call
---@param tool_call table
---@return string
function M.short_title(tool_call)
  local kind = fmt_kind(tool_call.kind or "tool")
  local p = diff_path(tool_call)
  if p then
    return ("%s: %s"):format(kind, relpath(p))
  end

  local t = tool_call.title or "Tool call"
  -- strip “ => …” preview
  t = t:gsub("%s*=>.*$", "")
  -- If "name: something", keep the name only
  local before = t:match("^%s*([^:]+)%s*:")
  if before then
    t = before
  end
  t = t:gsub("%s+$", "")
  if #t > 80 then
    t = t:sub(1, 77) .. "..."
  end
  return ("%s: %s"):format(kind, t)
end

---Extract content summary from various tool call content types
---@param tool_call table
---@return string|nil
local function extract_content_summary(tool_call)
  local contents = tool_call.content
  if type(contents) ~= "table" then
    return nil
  end

  local summaries = {}

  for _, c in ipairs(contents) do
    if c.type == "diff" then
      local path = c.path and relpath(c.path) or "file"
      local old_lines = vim.split(c.oldText or "", "\n", { plain = true })
      local new_lines = vim.split(c.newText or "", "\n", { plain = true })
      local delta = #new_lines - #old_lines

      if delta > 0 then
        table.insert(summaries, ("Edited %s (+%d lines)"):format(path, delta))
      elseif delta < 0 then
        table.insert(summaries, ("Edited %s (-%d lines)"):format(path, math.abs(delta)))
      else
        table.insert(summaries, ("Edited %s"):format(path))
      end
    elseif c.type == "content" then
      local text = M.extract_text(c.content)
      if text and text ~= "" then
        table.insert(summaries, text)
      end
    end
  end

  if #summaries > 0 then
    return table.concat(summaries, "; ")
  end

  return nil
end

---Summarize the content of a tool call (legacy function for compatibility)
---@param tool_call table
---@return string|nil
function M.summarize_tool_content(tool_call)
  return extract_content_summary(tool_call)
end

---Generate a smart summary based on tool kind and content
---@param tool_call table
---@param adapter CodeCompanion.ACPAdapter
---@return string
local function generate_smart_summary(tool_call, adapter)
  local kind = tool_call.kind or "tool"
  local status = tool_call.status or "pending"
  local show_verbose_output = adapter.opts and adapter.opts.verbose_output and adapter.opts.verbose_output == true

  -- Get base title (use enhanced version for better handling)
  local title = M.enhanced_title(tool_call)

  if status == "pending" or status == "in_progress" or not show_verbose_output then
    return title
  end

  -- Generate detailed summary based on kind
  local content_summary = extract_content_summary(tool_call)

  if kind == "read" then
    if status == "completed" and content_summary and content_summary ~= "" then
      -- For read operations, show a snippet of what was read
      return title .. " — " .. content_summary
    else
      return title
    end
  elseif kind == "edit" or kind == "write" then
    if status == "completed" and content_summary then
      return content_summary
    else
      return title
    end
  elseif kind == "execute" then
    if status == "completed" and content_summary and content_summary ~= "" then
      return title .. " — " .. content_summary
    else
      return title
    end
  elseif kind == "search" then
    if status == "completed" and content_summary and content_summary ~= "" then
      return title .. " — " .. content_summary
    else
      return title
    end
  elseif kind == "fetch" then
    if status == "completed" and content_summary and content_summary ~= "" then
      return title .. " — " .. content_summary
    else
      return title
    end
  end

  -- Fallback to generic handling
  return title
end

---Create a one-line message for tool-call events
---@param tool_call table
---@param adapter CodeCompanion.ACPAdapter
---@return string
function M.tool_message(tool_call, adapter)
  -- Normalize the tool call to handle inconsistent data
  local normalized = M.normalize_tool_call(tool_call)
  return generate_smart_summary(normalized, adapter)
end

---Create a one-line message for file-write
---@param info table
---@return string
function M.fs_write_message(info)
  local path = relpath(info.path or "")
  local bytes = tonumber(info.bytes or 0) or 0
  return ("Wrote %d bytes to %s"):format(bytes, path ~= "" and path or "file")
end

---Enhanced title generation that handles more edge cases
---@param tool_call table
---@return string
function M.enhanced_title(tool_call)
  local kind = fmt_kind(tool_call.kind or "tool")

  -- Check for diff path first
  local p = diff_path(tool_call)
  if p then
    return ("%s: %s"):format(kind, relpath(p))
  end

  -- Check locations for file paths
  if tool_call.locations and #tool_call.locations > 0 then
    local location = tool_call.locations[1]
    if location and location.path then
      return ("%s: %s"):format(kind, relpath(location.path))
    end
  end

  -- Extract operation from title
  local operation = extract_operation(tool_call.title)

  -- Truncate if too long
  if #operation > 60 then
    operation = operation:sub(1, 57) .. "..."
  end

  return ("%s: %s"):format(kind, operation)
end

---Validate and normalize tool call data
---@param tool_call table
---@return table Normalized tool call
function M.normalize_tool_call(tool_call)
  if type(tool_call) ~= "table" then
    return {
      toolCallId = "unknown",
      title = "Invalid tool call",
      kind = "other",
      status = "failed",
      content = {},
      locations = {},
    }
  end

  return {
    toolCallId = tool_call.toolCallId or "unknown",
    title = tool_call.title or "Tool call",
    kind = tool_call.kind or "other",
    status = tool_call.status or "pending",
    content = tool_call.content or {},
    locations = tool_call.locations or {},
  }
end

return M
