local file_utils = require("codecompanion.utils.files")
local fmt = string.format
local tool_helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

---@class UpdateFileChunk
---@field old_lines string[]
---@field new_lines string[]
---@field change_context string|nil
---@field is_end_of_file boolean|nil

---@class Hunk
---@field type "add"|"delete"|"update"
---@field path string
---@field contents string|nil
---@field move_path string|nil
---@field chunks UpdateFileChunk[]|nil

---@class CodeCompanion.Tool.ApplyPatch
---@field name string
---@field cmds table
---@field schema table
---@field system_prompt string
---@field output table
---@field opts table

local function strip_heredoc(input)
  local heredoc_pattern = "^(?:cat%s+)?<<['\"]?(%w+)['\"]?%s*\n([%s%S]*?)\n%1%s*$"
  local match = input:match(heredoc_pattern)
  if match then
    return match
  end
  return input
end

local function normalize_unicode(str)
  if not str then
    return ""
  end
  local s = str:gsub("[\u{2018}\u{2019}\u{201A}\u{201B}]", "'")
  s = s:gsub("[\u{201C}\u{201D}\u{201E}\u{201F}]", '"')
  s = s:gsub("[\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}]", "-")
  s = s:gsub("\u{2026}", "...")
  s = s:gsub("\u{00A0}", " ")
  return s
end

local function try_match(lines, pattern, start_index, compare_fn, eof)
  if eof then
    local match_idx = #lines - #pattern + 1
    if match_idx >= start_index then
      local matches = true
      for j = 1, #pattern do
        if not compare_fn(lines[match_idx + j - 1], pattern[j]) then
          matches = false
          break
        end
      end
      if matches then
        return match_idx
      end
    end
    return -1
  end

  for i = start_index, #lines - #pattern + 1 do
    local matches = true
    for j = 1, #pattern do
      if not compare_fn(lines[i + j - 1], pattern[j]) then
        matches = false
        break
      end
    end
    if matches then
      return i
    end
  end

  return -1
end

local function seek_sequence(lines, pattern, start_index, eof)
  if #pattern == 0 then
    if eof then
      return #lines + 1
    end
    return -1
  end

  -- Pass 1: exact match
  local exact = try_match(lines, pattern, start_index, function(a, b)
    return a == b
  end, eof)
  if exact ~= -1 then
    return exact
  end

  -- Pass 2: rstrip
  local rstrip = try_match(lines, pattern, start_index, function(a, b)
    return (a or ""):gsub("%s*$", "") == (b or ""):gsub("%s*$", "")
  end, eof)
  if rstrip ~= -1 then
    return rstrip
  end

  -- Pass 3: trim
  local trim = try_match(lines, pattern, start_index, function(a, b)
    return (a or ""):gsub("^%s*(.-)%s*$", "%1") == (b or ""):gsub("^%s*(.-)%s*$", "%1")
  end, eof)
  if trim ~= -1 then
    return trim
  end

  -- Pass 4: normalized
  local normalized = try_match(lines, pattern, start_index, function(a, b)
    return normalize_unicode((a or ""):gsub("^%s*(.-)%s*$", "%1"))
      == normalize_unicode((b or ""):gsub("^%s*(.-)%s*$", "%1"))
  end, eof)

  return normalized
end

local function count_sequences(lines, pattern, start_index, eof)
  local count = 0
  local current_start = start_index
  while true do
    local match = seek_sequence(lines, pattern, current_start, eof)
    if match == -1 then
      break
    end
    count = count + 1
    current_start = match + #pattern + 1
    if eof and match == #lines - #pattern + 1 then
      break
    end
  end
  return count
end

local function parse_patch(patch_text)
  local cleaned = strip_heredoc(patch_text:gsub("^%s*(.-)%s*$", "%1"))
  local lines = {}
  for line in cleaned:gmatch("([^\n]*)\n?") do
    table.insert(lines, line)
  end

  local begin_marker = "*** Begin Patch"
  local end_marker = "*** End Patch"
  local begin_idx, end_idx = -1, -1

  for i, line in ipairs(lines) do
    if line:match("^%s*" .. begin_marker .. "%s*$") then
      begin_idx = i
    end
    if line:match("^%s*" .. end_marker .. "%s*$") then
      end_idx = i
    end
  end

  if begin_idx == -1 or end_idx == -1 or begin_idx >= end_idx then
    error("Invalid patch format: missing Begin/End markers")
  end

  local hunks = {}
  local i = begin_idx + 1
  while i < end_idx do
    local line = lines[i]
    if line:match("^*** Add File: (.+)") then
      local path = line:match("^*** Add File: (.+)")
      local contents = ""
      i = i + 1
      while i < end_idx and not lines[i]:match("^***") do
        if lines[i]:match("^%+") then
          contents = contents .. lines[i]:sub(2) .. "\n"
        end
        i = i + 1
      end
      if contents:match("\n$") then
        contents = contents:sub(1, -2)
      end
      table.insert(hunks, { type = "add", path = path, contents = contents })
    elseif line:match("^*** Delete File: (.+)") then
      local path = line:match("^*** Delete File: (.+)")
      table.insert(hunks, { type = "delete", path = path })
      i = i + 1
    elseif line:match("^*** Update File: (.+)") then
      local path = line:match("^*** Update File: (.+)")
      local move_path = nil
      i = i + 1
      if i < end_idx and lines[i]:match("^*** Move to: (.+)") then
        move_path = lines[i]:match("^*** Move to: (.+)")
        i = i + 1
      end
      local chunks = {}
      while i < end_idx and not lines[i]:match("^***") do
        if lines[i]:match("^@@ (.+)") then
          local context = lines[i]:match("^@@ (.+)")
          i = i + 1
          local old_lines, new_lines = {}, {}
          local is_end_of_file = false
          while i < end_idx and not lines[i]:match("^@@") and not lines[i]:match("^***") do
            if lines[i] == "*** End of File" then
              is_end_of_file = true
              i = i + 1
              break
            elseif lines[i]:match("^ ") then
              local content = lines[i]:sub(2)
              table.insert(old_lines, content)
              table.insert(new_lines, content)
            elseif lines[i]:match("^-") then
              table.insert(old_lines, lines[i]:sub(2))
            elseif lines[i]:match("^%+") then
              table.insert(new_lines, lines[i]:sub(2))
            end
            i = i + 1
          end
          table.insert(
            chunks,
            { old_lines = old_lines, new_lines = new_lines, change_context = context, is_end_of_file = is_end_of_file }
          )
        else
          i = i + 1
        end
      end
      table.insert(hunks, { type = "update", path = path, move_path = move_path, chunks = chunks })
    else
      i = i + 1
    end
  end

  return { hunks = hunks }
end

local function write_file(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local f = io.open(path, "w")
  if not f then
    error("Could not open file for writing: " .. path)
  end
  f:write(content)
  f:close()
end

---Load prompt from markdown file
---@return string The prompt content
local function load_prompt()
  local source_path = debug.getinfo(1, "S").source:sub(2)
  local dir = vim.fn.fnamemodify(source_path, ":h")
  local prompt_path = dir .. "/apply_patch.md"
  if vim.fn.filereadable(prompt_path) == 0 then
    error("Prompt file not found: " .. prompt_path)
  end
  return table.concat(vim.fn.readfile(prompt_path), "\n")
end

local function handle_add(path, hunk)
  write_file(path, hunk.contents or "")
  return "A " .. path
end

local function handle_delete(path, hunk)
  if vim.fn.getfsize(path) == -1 then
    return { status = "error", data = "File to delete does not exist: " .. path }
  end
  vim.fn.delete(path, "rf")
  return "D " .. path
end

local function handle_update(path, hunk)
  if vim.fn.getfsize(path) == -1 then
    return { status = "error", data = "File to update does not exist: " .. path }
  end

  local lines = {}
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do
      table.insert(lines, line)
    end
    f:close()
  end

  local current_idx = 1
  for _, chunk in ipairs(hunk.chunks) do
    local search_start = current_idx

    if chunk.change_context then
      local ctx_match = seek_sequence(lines, { chunk.change_context }, search_start, chunk.is_end_of_file)
      if ctx_match == -1 then
        return {
          status = "error",
          data = fmt("Could not find context '%s' in %s", chunk.change_context, path),
        }
      end
      search_start = ctx_match + 1
    end

    local match_idx = seek_sequence(lines, chunk.old_lines, search_start, chunk.is_end_of_file)

    if match_idx == -1 and #chunk.old_lines == 0 then
      match_idx = search_start
    end

    if match_idx == -1 then
      return { status = "error", data = "Could not find match for hunk in " .. path }
    end

    -- Check for multiple matches to ensure uniqueness
    if #chunk.old_lines > 0 then
      local matches = count_sequences(lines, chunk.old_lines, search_start, chunk.is_end_of_file)
      if matches > 1 then
        return {
          status = "error",
          data = fmt(
            "Found multiple matches for oldString in %s. Provide more surrounding context to make the match unique.",
            path
          ),
        }
      end
    end

    local before = {}
    for i = 1, match_idx - 1 do
      table.insert(before, lines[i])
    end

    local after = {}
    for i = match_idx + #chunk.old_lines, #lines do
      table.insert(after, lines[i])
    end

    local new_lines = {}
    for i = 1, #before do
      table.insert(new_lines, before[i])
    end
    for i = 1, #chunk.new_lines do
      table.insert(new_lines, chunk.new_lines[i])
    end
    for i = 1, #after do
      table.insert(new_lines, after[i])
    end

    lines = new_lines
    current_idx = match_idx + #chunk.new_lines
  end

  local final_content = table.concat(lines, "\n")
  if #lines > 0 and lines[#lines] ~= "" then
    final_content = final_content .. "\n"
  end

  local target_path = path
  if hunk.move_path then
    local normalized_move_path = file_utils.validate_and_normalize_path(hunk.move_path)
    if not normalized_move_path then
      return { status = "error", data = "Invalid move path: " .. hunk.move_path }
    end
    target_path = normalized_move_path
  end

  write_file(target_path, final_content)
  if hunk.move_path then
    vim.fn.delete(path, "rf")
  end
  return "M " .. target_path
end

local function execute_apply_patch(self, args, input)
  if not args.patchText then
    return { status = "error", data = "patchText is required" }
  end

  local success, result = pcall(parse_patch, args.patchText)
  if not success then
    return { status = "error", data = "Patch parsing failed: " .. result }
  end

  local hunks = result.hunks
  if #hunks == 0 then
    return { status = "error", data = "No hunks found in patch" }
  end

  local summary = {}

  for _, hunk in ipairs(hunks) do
    local path = file_utils.validate_and_normalize_path(hunk.path)

    if not path then
      table.insert(summary, "Skipped (invalid path): " .. tostring(hunk.path))
    else
      local result
      if hunk.type == "add" then
        result = handle_add(path, hunk)
      elseif hunk.type == "delete" then
        result = handle_delete(path, hunk)
      elseif hunk.type == "update" then
        result = handle_update(path, hunk)
      end

      if type(result) == "table" and result.status == "error" then
        return result
      end
      table.insert(summary, result)
    end
  end

  return {
    status = "success",
    data = "Success. Updated the following files:\n" .. table.concat(summary, "\n"),
  }
end

local PROMPT = load_prompt()

local tool = {
  name = "apply_patch",
  cmds = {
    ---Execute the apply patch commands
    ---@param self CodeCompanion.Tool.ApplyPatch
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    execute_apply_patch,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "apply_patch",
      description = "Apply a structured patch to the codebase to add, delete, or update files.",
      parameters = {
        type = "object",
        properties = {
          patchText = {
            type = "string",
            description = "The full patch text that describes all changes to be made",
          },
        },
        required = { "patchText" },
      },
    },
  },
  system_prompt = PROMPT,
  output = {
    cmd_string = function(self, opts)
      return "apply_patch"
    end,
    prompt = function(self, meta)
      return "Apply patch to codebase?"
    end,
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      chat:add_tool_output(self, stdout[1])
    end,
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      chat:add_tool_output(self, errors)
    end,
    rejected = function(self, meta)
      tool_helpers.rejected(self, meta)
    end,
  },
  opts = {
    require_approval_before = true,
  },
}

tool.parse_patch = parse_patch
return tool
