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

---Summarize the content of a tool call
---@param contents table|nil
---@return string|nil
function M.summarize_tool_content(contents)
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
        return t
      end
    end
  end
  return nil
end

---Create a one-line message for tool-call events
---@param tool_call table
---@return string
function M.tool_message(tool_call)
  local status = tool_call.status or "pending"
  local title = M.short_title(tool_call)
  if status == "completed" then
    local summary = M.summarize_tool_content(tool_call.content)
    return summary or (title .. " — completed")
  elseif status == "in_progress" then
    return title .. " — running"
  elseif status == "failed" then
    local summary = M.summarize_tool_content(tool_call.content)
    return summary and (title .. " — failed: " .. summary) or (title .. " — failed")
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
