local M = {}

M.FORMAT_PROMPT = [[*** Begin Patch
[PATCH]
*** End Patch

The `[PATCH]` is the series of diffs to be applied for each change in the file. Each diff should be in this format:

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
Example with multiple blocks of changes and `@@` identifiers:

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
Be mindful that the user may have shared attachments that contain line numbers, but these should not be used in your patch.
IMPORTANT: Be mindful that the user may have shared attachments that contain line numbers, but these should NEVER be used in your patch. Always use the contextual format described above.]]

---@class Change
---@field focus string[] Identifiers or lines for providing large context before a change
---@field pre string[] Unchanged lines immediately before edits
---@field old string[] Lines to be removed
---@field new string[] Lines to be added
---@field post string[] Unchanged lines just after edits

---Create and return a new (empty) Change table instance.
---@param focus? string[] Optional focus lines for context
---@param pre? string[] Optional pre-context lines
---@return Change New change object
local function get_new_change(focus, pre)
  return {
    focus = focus or {},
    pre = pre or {},
    old = {},
    new = {},
    post = {},
  }
end

---Parse a patch string into a list of Change objects.
---@param patch string Patch containing the changes
---@return Change[] List of parsed change blocks
local function parse_changes_from_patch(patch)
  local changes = {}
  local change = get_new_change()
  local lines = vim.split(patch, "\n", { plain = true })
  for i, line in ipairs(lines) do
    if vim.startswith(line, "@@") then
      if #change.old > 0 or #change.new > 0 then
        -- @@ after any edits is a new change block
        table.insert(changes, change)
        change = get_new_change()
      end
      -- focus name can be empty too to signify new blocks
      local focus_name = vim.trim(line:sub(3))
      if focus_name and #focus_name > 0 then
        change.focus[#change.focus + 1] = focus_name
      end
    elseif line == "" and lines[i + 1] and lines[i + 1]:match("^@@") then
      -- empty lines can be part of pre/post context
      -- we treat empty lines as new change block and not as post context
      -- only when the next line uses @@ identifier
      table.insert(changes, change)
      change = get_new_change()
    elseif line:sub(1, 1) == "-" then
      if #change.post > 0 then
        -- edits after post edit lines are new block of changes with same focus
        table.insert(changes, change)
        change = get_new_change(change.focus, change.post)
      end
      change.old[#change.old + 1] = line:sub(2)
    elseif line:sub(1, 1) == "+" then
      if #change.post > 0 then
        -- edits after post edit lines are new block of changes with same focus
        table.insert(changes, change)
        change = get_new_change(change.focus, change.post)
      end
      change.new[#change.new + 1] = line:sub(2)
    elseif #change.old == 0 and #change.new == 0 then
      change.pre[#change.pre + 1] = line
    elseif #change.old > 0 or #change.new > 0 then
      change.post[#change.post + 1] = line
    end
  end
  table.insert(changes, change)
  return changes
end

---Parse the full raw string from LLM for all patches, returning all Change objects parsed.
---@param raw string Raw text containing patch blocks
---@return Change[], boolean All parsed Change objects, and whether the patch was properly parsed
function M.parse_changes(raw)
  local patches = {}
  for patch in raw:gmatch("%*%*%* Begin Patch%s+(.-)%s+%*%*%* End Patch") do
    table.insert(patches, patch)
  end

  local had_begin_end_markers = true
  if #patches == 0 then
    --- LLMs miss the begin / end markers sometimes
    --- let's assume the raw content was correctly wrapped in these cases
    --- setting a `markers_error` so that we can show this error in case the patch fails to apply
    had_begin_end_markers = false
    table.insert(patches, raw)
  end

  local all_changes = {}
  for _, patch in ipairs(patches) do
    local changes = parse_changes_from_patch(patch)
    for _, change in ipairs(changes) do
      table.insert(all_changes, change)
    end
  end
  return all_changes, had_begin_end_markers
end

---Score how many lines from needle match haystack lines.
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

---Get overall score for placing change at a given index.
---@param lines string[] File lines
---@param change Change To match
---@param i integer Line position
---@return number Score from 0.0 to 1.0
local function get_match_score(lines, change, i)
  local max_score = (#change.focus * 2 + #change.pre + #change.old + #change.post) * 10
  local score = get_focus_score(lines, i, change.focus)
    + get_score(lines, i - #change.pre, change.pre)
    + get_score(lines, i, change.old)
    + get_score(lines, i + #change.old, change.post)
  return score / max_score
end

---Determine best insertion spot for a Change and its match score.
---@param lines string[] File lines
---@param change Change Patch block
---@return integer, number location (1-based), Score (0-1)
local function get_best_location(lines, change)
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
    local score = get_match_score(lines, change, i)
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

---Get the location where a change would be applied without actually applying it
---@param lines string[] File lines
---@param change Change Edit description
---@return integer|nil location The line number (1-based) where the change would be applied
function M.get_change_location(lines, change)
  local location, score = get_best_location(lines, change)
  if score < 0.5 then
    return nil
  end
  return location
end

---Apply a Change object to the file lines. Returns nil if not confident.
---@param lines string[] Lines before patch
---@param change Change Edit description
---@return string[]|nil New file lines (or nil if patch can't be confidently placed)
function M.apply_change(lines, change)
  local location, score = get_best_location(lines, change)
  if score < 0.5 then
    return
  end
  local new_lines = {}
  -- add lines before diff
  for k = 1, location - 1 do
    new_lines[#new_lines + 1] = lines[k]
  end
  -- add new lines
  local fix_spaces
  -- infer adjustment of spaces from the delete line
  if score ~= 1 and #change.old > 0 then
    if change.old[1] == " " .. lines[location] then
      -- diff patch added and extra space on left
      fix_spaces = function(ln)
        return ln:sub(2)
      end
    elseif #change.old[1] < #lines[location] then
      -- diff removed spaces on left
      local prefix = string.rep(" ", #lines[location] - #change.old[1])
      fix_spaces = function(ln)
        return prefix .. ln
      end
    end
  end
  for _, ln in ipairs(change.new) do
    if fix_spaces then
      ln = fix_spaces(ln)
    end
    new_lines[#new_lines + 1] = ln
  end
  -- add remaining lines
  for k = location + #change.old, #lines do
    new_lines[#new_lines + 1] = lines[k]
  end
  return new_lines
end

---Join a list of lines, prefixing each optionally.
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

---Format a Change block as a string for output or logs.
---@param change Change To render
---@return string Formatted string
function M.get_change_string(change)
  local parts = {
    prefix_join(change.focus, "\n", "@@"),
    prefix_join(change.pre, "\n"),
    prefix_join(change.old, "\n", "-"),
    prefix_join(change.new, "\n", "+"),
    prefix_join(change.post, "\n"),
  }
  local non_empty = {}
  for _, part in ipairs(parts) do
    if part then
      table.insert(non_empty, part)
    end
  end
  return table.concat(non_empty, "\n")
end

return M
