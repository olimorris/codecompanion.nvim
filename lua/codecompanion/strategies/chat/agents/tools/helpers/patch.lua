local log = require("codecompanion.utils.log")

---@class CodeCompanion.Patch
---@field prompt string The prompt text explaining the patch format to the LLM
---@field parse_edits fun(raw: string): CodeCompanion.Patch.Edit[], boolean, nil|string Parse raw LLM output into changes and whether markers were found
---@field apply fun(lines: string[], edit: CodeCompanion.Patch.Edit): string[]|nil,string|nil Apply an edit to file lines, returns nil if can't be confidently applied
---@field start_line fun(lines: string[], edit: CodeCompanion.Patch.Edit): integer|nil Get the line number (1-based) where edit would be applied
---@field format fun(edit: CodeCompanion.Patch.Edit): string Format an edit object as a readable string for display/logging
local Patch = {}

Patch.prompt = [[*** Begin Patch
[PATCH]
*** End Patch

The `[PATCH]` is the series of diffs to be applied for each edit in the file. Each diff should be in this format:

 [3 lines of pre-context]
-[old code]
+[new code]
 [3 lines of post-context]

The context blocks are 3 lines of existing code, immediately before and after the modified lines of code.
Lines to be modified should be prefixed with a `+` or `-` sign.
Unmodified lines used in context should begin with an empty space ` `.

For example, to add a subtract method to a calculator class in Python:

*** Begin Patch
 def add(self, value):
     self.result += value
     return self.result

+def subtract(self, value):
+    self.result -= value
+    return self.result
+
 def multiply(self, value):
     self.result *= value
     return self.result
*** End Patch

Multiple blocks of diffs should be separated by an empty line and `@@[identifier]` as detailed below.
The immediately preceding and after context lines are enough to locate the lines to edit. DO NOT USE line numbers anywhere in the patch.
You can use `@@[identifier]` to define a larger context in case the immediately before and after context is not sufficient to locate the edits. Example:

@@class BaseClass(models.Model):
 [3 lines of pre-context]
-	pass
+	raise NotImplementedError()
 [3 lines of post-context]

You can also use multiple `@@[identifiers]` to provide the right context if a single `@@` is not sufficient.
Example with multiple blocks of edits and `@@` identifiers:

*** Begin Patch
@@class BaseClass(models.Model):
@@	def search():
-		pass
+		raise NotImplementedError()

@@class Subclass(BaseClass):
@@	def search():
-		pass
+		raise NotImplementedError()
*** End Patch

This format is similar to the `git diff` format; the difference is that `@@[identifiers]` uses the unique line identifiers from the preceding code instead of line numbers. We don't use line numbers anywhere since the before and after context, and `@@` identifiers are enough to locate the edits.
IMPORTANT: Be mindful that the user may have shared attachments that contain line numbers, but these should NEVER be used in your patch. Always use the contextual format described above.]]

---@class CodeCompanion.Patch.Edit
---@field focus string[] Identifiers or lines for providing large context before an edit
---@field pre string[] Unchanged lines immediately before edits
---@field old string[] Lines to be removed
---@field new string[] Lines to be added
---@field post string[] Unchanged lines just after edits

---Create and return a new (empty) edit
---@param focus? string[] Optional focus lines for context
---@param pre? string[] Optional pre-context lines
---@return CodeCompanion.Patch.Edit New edit object
local function get_new_edit(focus, pre)
  return {
    focus = focus or {},
    pre = pre or {},
    old = {},
    new = {},
    post = {},
  }
end

---Parse a patch string into a list of edits
---@param patch string Patch containing the edits
---@return CodeCompanion.Patch.Edit[] List of parsed edit blocks
local function parse_edits_from_patch(patch)
  local edits = {}
  local edit = get_new_edit()

  local lines = vim.split(patch, "\n", { plain = true })
  for i, line in ipairs(lines) do
    if vim.startswith(line, "@@") then
      if #edit.old > 0 or #edit.new > 0 then
        -- @@ after any edits is a new edit block
        table.insert(edits, edit)
        edit = get_new_edit()
      end
      -- focus name can be empty too to signify new blocks
      local focus_name = vim.trim(line:sub(3))
      if focus_name and #focus_name > 0 then
        edit.focus[#edit.focus + 1] = focus_name
      end
    elseif line == "" and lines[i + 1] and lines[i + 1]:match("^@@") then
      -- empty lines can be part of pre/post context
      -- we treat empty lines as a new edit block and not as post context
      -- only when the next line uses @@ identifier
      -- skip this line and do nothing
      do
      end
    elseif line:sub(1, 1) == "-" then
      if #edit.post > 0 then
        -- edits after post edit lines are new block of changes with same focus
        table.insert(edits, edit)
        edit = get_new_edit(edit.focus, edit.post)
      end
      edit.old[#edit.old + 1] = line:sub(2)
    elseif line:sub(1, 1) == "+" then
      if #edit.post > 0 then
        -- edits after post edit lines are new block of changes with same focus
        table.insert(edits, edit)
        edit = get_new_edit(edit.focus, edit.post)
      end
      edit.new[#edit.new + 1] = line:sub(2)
    elseif #edit.old == 0 and #edit.new == 0 then
      edit.pre[#edit.pre + 1] = line
    elseif #edit.old > 0 or #edit.new > 0 then
      edit.post[#edit.post + 1] = line
    end
  end
  table.insert(edits, edit)
  return edits
end

---Parse the edits from the LLM for all patches, returning all parsed edits
---@param raw string Raw text containing patch blocks
---@return CodeCompanion.Patch.Edit, boolean, string|nil All parsed edits, and whether the patch was properly parsed
function Patch.parse_edits(raw)
  local patches = {}
  for patch in raw:gmatch("%*%*%* Begin Patch[\r\n]+(.-)[\r\n]+%*%*%* End Patch") do
    table.insert(patches, patch)
  end

  local had_begin_end_markers = true
  local parse_error = nil

  if #patches == 0 then
    --- LLMs miss the begin / end markers sometimes
    --- let's assume the raw content was correctly wrapped in these cases
    --- setting a `markers_error` so that we can show this error in case the patch fails to apply
    had_begin_end_markers = false
    table.insert(patches, raw)
    parse_error = "Missing Begin/End patch markers - assuming entire content is a patch"
  end

  local all_edits = {}
  for _, patch in ipairs(patches) do
    local edits = parse_edits_from_patch(patch)
    for _, edit in ipairs(edits) do
      table.insert(all_edits, edit)
    end
  end
  return all_edits, had_begin_end_markers, parse_error
end

---Score how many lines from needle match haystack lines
---@param haystack string[] All file lines
---@param pos integer Starting index to check (1-based)
---@param needle string[] Lines to match
---@return integer Score: 10 per perfect line, or 9 per trimmed match
local function get_score(haystack, pos, needle)
  local score = 0
  for i, needle_line in ipairs(needle) do
    local hayline = haystack[pos + i - 1]
    if hayline == needle_line then
      score = score + 10
    elseif hayline and vim.trim(hayline) == vim.trim(needle_line) then
      score = score + 9
    end
  end
  return score
end

---Compute the match score for focus lines above a position.
---@param lines string[] Lines of source file
---@param before_pos integer Scan up to this line (exclusive; 1-based)
---@param focus string[] Focus lines/context
---@return integer Score: 20 per matching focus line before position
local function get_focus_score(lines, before_pos, focus)
  local start = 1
  local score = 0
  for _, focus_line in ipairs(focus) do
    for k = start, before_pos - 1 do
      if focus_line == lines[k] or (vim.trim(focus_line) == vim.trim(lines[k])) then
        score = score + 20
        start = k
        break
      end
    end
  end
  return score
end

---Get the overall score for placing an edit on a given line
---@param lines string[] File lines
---@param edit CodeCompanion.Patch.Edit To match
---@param i integer Line position
---@return number Score from 0.0 to 1.0
local function get_match_score(lines, edit, i)
  local max_score = (#edit.focus * 2 + #edit.pre + #edit.old + #edit.post) * 10
  local score = get_focus_score(lines, i, edit.focus)
    + get_score(lines, i - #edit.pre, edit.pre)
    + get_score(lines, i, edit.old)
    + get_score(lines, i + #edit.old, edit.post)
  return score / max_score
end

---Determine best insertion spot for an edit and its match score
---@param lines string[] File lines
---@param edit CodeCompanion.Patch.Edit Patch block
---@return integer, number location (1-based), Score (0-1)
local function get_best_location(lines, edit)
  -- try applying patch in flexible spaces mode
  -- there is no standardised way to of spaces in diffs
  -- python differ specifies a single space after +/-
  -- while gnu udiff uses no spaces
  --
  -- and LLM models (especially Claude) sometimes strip
  -- long spaces on the left in case of large nestings (eg html)
  -- trim_spaces mode solves all of these
  local best_location = 1
  local best_score = 0
  for i = 1, #lines + 1 do
    local score = get_match_score(lines, edit, i)
    if score == 1 then
      return i, 1
    end
    if score > best_score then
      best_location = i
      best_score = score
    end
  end
  return best_location, best_score
end

---Get the start line location where an edit would be applied without actually applying it
---@param lines string[] File lines
---@param edit CodeCompanion.Patch.Edit Edit description
---@return integer|nil location The line number (1-based) where the edit would be applied
function Patch.start_line(lines, edit)
  local location, score = get_best_location(lines, edit)
  if score < 0.5 then
    return nil
  end
  return location
end

---Check if an edit is a simple append operation for small/empty files
---@param lines string[] Current file lines
---@param edit CodeCompanion.Patch.Edit The edit to analyze
---@return boolean is_simple_append
---@return string[]? lines_to_append
local function is_simple_append(lines, edit)
  -- For empty files (containing only "")
  if #lines == 1 and lines[1] == "" then
    log:debug("[Patch] Empty file detected, treating as simple append")
    return true, edit.new
  end

  -- For small files with simple append patterns
  if #lines <= 5 and #edit.old == 0 and #edit.new > 0 then
    -- Check if pre-context matches the end of the file or is empty
    if #edit.pre == 0 then
      log:debug("[Patch] No pre-context, appending to end of small file")
      return true, edit.new
    end
    -- Check if pre-context matches the last lines of the file
    local matches = true
    local start_check = math.max(1, #lines - #edit.pre + 1)
    for i, pre_line in ipairs(edit.pre) do
      local file_line = lines[start_check + i - 1]
      if not file_line or (vim.trim(file_line) ~= vim.trim(pre_line)) then
        matches = false
        break
      end
    end

    if matches then
      log:debug("[Patch] Pre-context matches, treating as simple append")
      return true, edit.new
    end
  end

  return false, nil
end

---Apply an edit to the file lines. Returns nil if not confident
---@param lines string[] Lines before patch
---@param edit CodeCompanion.Patch.Edit Edit description
---@return string[]|nil,string|nil New file lines (or nil if patch can't be confidently placed)
function Patch.apply(lines, edit)
  -- Handle small files and empty files with special logic
  if #lines <= 5 then
    local is_append, append_lines = is_simple_append(lines, edit)
    if is_append and append_lines then
      log:debug("[Patch] Using simple append for small file")
      local new_lines = {}
      -- For empty files, don't include the empty string
      if #lines == 1 and lines[1] == "" then
        for _, line in ipairs(append_lines) do
          table.insert(new_lines, line)
        end
      else
        -- Copy existing lines and append new ones
        for _, line in ipairs(lines) do
          table.insert(new_lines, line)
        end
        for _, line in ipairs(append_lines) do
          table.insert(new_lines, line)
        end
      end
      log:debug("[Patch] Small file append successful, new line count: %d", #new_lines)
      return new_lines
    end
  end
  local location, score = get_best_location(lines, edit)
  if score < 0.5 then
    local error_msg = string.format(
      "Could not confidently apply edit (confidence: %.1f%%). %s",
      score * 100,
      score < 0.2 and "The context doesn't match the file content."
        or "Try providing more specific context or checking for formatting differences."
    )
    log:debug("[Patch] Low confidence score (%.2f), edit details: %s", score, Patch.format(edit))
    return nil, error_msg
  end
  local new_lines = {}
  -- add lines before diff
  for k = 1, location - 1 do
    new_lines[#new_lines + 1] = lines[k]
  end
  -- add new lines
  local fix_spaces
  -- infer adjustment of spaces from the delete line
  if score ~= 1 and #edit.old > 0 then
    if edit.old[1] == " " .. lines[location] then
      -- diff patch added and extra space on left
      fix_spaces = function(ln)
        return ln:sub(2)
      end
    elseif #edit.old[1] < #lines[location] then
      -- diff removed spaces on left
      local prefix = string.rep(" ", #lines[location] - #edit.old[1])
      fix_spaces = function(ln)
        return prefix .. ln
      end
    end
  end
  for _, ln in ipairs(edit.new) do
    if fix_spaces then
      ln = fix_spaces(ln)
    end
    new_lines[#new_lines + 1] = ln
  end
  -- add remaining lines
  for k = location + #edit.old, #lines do
    new_lines[#new_lines + 1] = lines[k]
  end
  return new_lines, nil
end

---Join a list of lines, prefixing each optionally
---@param list string[] List of lines
---@param sep string Separator (e.g., "\n")
---@param prefix? string Optional prefix for each line
---@return string|false Result string or false if list is empty
local function prefix_join(list, sep, prefix)
  if #list == 0 then
    return false
  end

  if prefix then
    for i = 1, #list do
      list[i] = prefix .. list[i]
    end
  end
  return table.concat(list, sep)
end

---Format an edit block as a string for output or logs
---@param edit CodeCompanion.Patch.Edit To render
---@return string Formatted string
function Patch.format(edit)
  local parts = {
    prefix_join(edit.focus, "\n", "@@"),
    prefix_join(edit.pre, "\n"),
    prefix_join(edit.old, "\n", "-"),
    prefix_join(edit.new, "\n", "+"),
    prefix_join(edit.post, "\n"),
  }
  local non_empty = {}
  for _, part in ipairs(parts) do
    if part then
      table.insert(non_empty, part)
    end
  end
  return table.concat(non_empty, "\n")
end

return Patch
