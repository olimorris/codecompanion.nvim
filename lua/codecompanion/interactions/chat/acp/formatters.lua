--[[
===============================================================================
    File:       codecompanion.interactions/chat/acp/formatters.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      Formats ACP tool calls into a single-line label for the chat buffer.

      Output rules:
        - Always single line (no triple backticks, no newlines)
        - Label format: "Kind: <target>" (e.g. "Read: config.json")
        - When `verbose_output` is set on the adapter, completed calls may
          append " — <summary>" or replace the label entirely (edits)
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local M = {}

local MAX_TITLE = 60
local MAX_TEXT = 100

---Normalize a path relative to cwd
---@param p string
---@return string
local function relpath(p)
  return vim.fs.normalize(vim.fn.fnamemodify(p or "", ":."))
end

---Collapse text to a single line and truncate
---@param text string
---@param max_length? number
---@return string
local function sanitize_text(text, max_length)
  if not text or text == "" then
    return ""
  end

  max_length = max_length or MAX_TEXT

  text = text:gsub("```[%w]*\n?", ""):gsub("```", "")
  text = text:gsub("\r?\n", " "):gsub("%s+", " ")
  text = text:match("^%s*(.-)%s*$") or ""

  if #text > max_length then
    text = text:sub(1, max_length - 3) .. "..."
  end

  return text
end

---Extract plain text from an ACP ContentBlock for display
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
    if type(block.resource.text) == "string" then
      return sanitize_text(block.resource.text)
    end
    if type(block.resource.uri) == "string" then
      return ("[resource: %s]"):format(block.resource.uri)
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

---Capitalise an ACP tool kind ("edit" → "Edit", "switch_mode" → "Switch mode")
---@param kind string|nil
---@return string
local function format_kind(kind)
  if not kind or kind == "" then
    return "Tool"
  end
  local s = kind:gsub("_", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
end

---Find the first diff content block in a tool call
---@param tool_call table
---@return table|nil
local function find_diff(tool_call)
  if type(tool_call.content) ~= "table" then
    return nil
  end
  for _, c in ipairs(tool_call.content) do
    if c and c.type == "diff" then
      return c
    end
  end
end

---Pull a meaningful command/operation out of a tool call title.
---Handles backtick-wrapped commands and strips trailing preview noise
---like " => …" or " — …" that some agents append.
---@param title string
---@return string
local function parse_title(title)
  if not title or title == "" then
    return "Tool call"
  end

  title = title:gsub("^%s*", "")

  local backtick_cmd = title:match("^`([^`]+)`")
  if backtick_cmd then
    return backtick_cmd
  end

  local quoted = title:match('^"([^"]+)"')
  if quoted then
    return quoted
  end

  title = title:gsub("%s*=>.*$", ""):gsub("%s*—.*$", "")

  local before_colon = title:match("^%s*([^:]+)%s*:")
  if before_colon and #before_colon < 40 then
    local after_colon = title:match("^%s*[^:]+%s*:%s*(.+)")
    if not (after_colon and (after_colon:match("^//") or after_colon:match("^https?://"))) then
      title = before_colon
    end
  end

  title = title:gsub("%s+$", "")
  if #title > MAX_TITLE then
    title = title:sub(1, MAX_TITLE - 3) .. "..."
  end

  return title ~= "" and title or "Tool call"
end

---Build the "Kind: <target>" label for a tool call.
---Preference order for target: diff path → first location path → parsed title.
---@param tool_call table
---@return string
local function build_label(tool_call)
  local kind = format_kind(tool_call.kind)

  local diff = find_diff(tool_call)
  if diff and type(diff.path) == "string" then
    return ("%s: %s"):format(kind, relpath(diff.path))
  end

  local location = tool_call.locations and tool_call.locations[1]
  if location and type(location.path) == "string" then
    return ("%s: %s"):format(kind, relpath(location.path))
  end

  return ("%s: %s"):format(kind, parse_title(tool_call.title))
end

---Build a verbose summary for an edit (replaces the label entirely)
---@param tool_call table
---@return string|nil
local function diff_summary(tool_call)
  local diff = find_diff(tool_call)
  if not diff then
    return nil
  end

  local path = diff.path and relpath(diff.path) or "file"
  local old_lines = vim.split(diff.oldText or "", "\n", { plain = true })
  local new_lines = vim.split(diff.newText or "", "\n", { plain = true })
  local delta = #new_lines - #old_lines

  if delta > 0 then
    return ("Edited %s (+%d lines)"):format(path, delta)
  elseif delta < 0 then
    return ("Edited %s (-%d lines)"):format(path, math.abs(delta))
  end
  return ("Edited %s"):format(path)
end

---Extract a one-line summary from a tool call's content blocks
---@param tool_call table
---@return string|nil
local function content_summary(tool_call)
  if type(tool_call.content) ~= "table" then
    return nil
  end

  local parts = {}
  for _, c in ipairs(tool_call.content) do
    if c.type == "content" then
      local text = M.extract_text(c.content)
      if text and text ~= "" then
        table.insert(parts, text)
      end
    end
  end

  if #parts > 0 then
    return table.concat(parts, "; ")
  end
end

---Strip backticks and shorten cwd-rooted paths for display in a markdown buffer
---@param text string
---@return string
local function clean_for_buffer(text)
  if not text or text == "" then
    return text
  end
  text = text:gsub("`", "")
  local cwd = vim.fn.getcwd()
  if cwd and cwd ~= "" then
    text = text:gsub(vim.pesc(cwd) .. "/", "")
  end
  return text
end

---Fill in defaults for missing tool call fields
---@param tool_call table
---@return table
local function normalize(tool_call)
  if type(tool_call) ~= "table" then
    return {
      content = {},
      kind = "other",
      locations = {},
      status = "failed",
      title = "Invalid tool call",
      toolCallId = "unknown",
    }
  end

  return {
    content = tool_call.content or {},
    kind = tool_call.kind or "other",
    locations = tool_call.locations or {},
    status = tool_call.status or "pending",
    title = tool_call.title or "Tool call",
    toolCallId = tool_call.toolCallId or "unknown",
  }
end

---Build the single-line display string for an ACP tool call
---@param tool_call table
---@param adapter CodeCompanion.ACPAdapter
---@return string
function M.tool_message(tool_call, adapter)
  local call = normalize(tool_call)
  local label = build_label(call)

  local verbose = adapter.opts and adapter.opts.verbose_output == true
  if not verbose or call.status ~= "completed" then
    return clean_for_buffer(label)
  end

  -- Edits get a custom summary that replaces the label entirely
  local diff = diff_summary(call)
  if diff then
    return clean_for_buffer(diff)
  end

  local summary = content_summary(call)
  if summary and summary ~= "" then
    return clean_for_buffer(label .. " — " .. summary)
  end

  return clean_for_buffer(label)
end

return M
