local M = {}

M.FORMAT_PROMPT = [[*** Begin Patch
[PATCH]
*** End Patch

The `[PATCH]` is the series of diffs to be applied for each change in the file. Each diff should be in this format:

[3 lines of pre-context]
-[old code]
+[new code]
[3 lines of post-context]

The context blocks are 3 lines of existing code, immediately before and after the modified lines of code. Lines to be modified should be prefixed with a `+` or `-` sign. Unchanged lines used for context starting with a `-` (such as comments in Lua) can be prefixed with a space ` `.

Multiple blocks of diffs should be separated by an empty line and `@@[identifier]` detailed below.

The linked context lines next to the edits are enough to locate the lines to edit. DO NOT USE line numbers anywhere in the patch.

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

This format is a bit similar to the `git diff` format; the difference is that `@@[identifiers]` uses the unique line identifiers from the preceding code instead of line numbers. We don't use line numbers anywhere since the before and after context, and `@@` identifiers are enough to locate the edits.
]]

---@class Change
---@field focus table list of lines before changes for larger context
---@field pre table list of unchanged lines just before edits
---@field old table list of lines to be removed
---@field new table list of lines to be added
---@field post table list of unchanged lines just after edits

---@class MatchOptions
---@field trim_spaces boolean trim spaces while comparing lines

--- Returns an new (empty) change table instance
---@param focus table|nil list of focus lines, used to create a new change set with similar focus
---@param pre table|nil list of pre lines to extend an existing change set
---@return Change
local function get_new_change(focus, pre)
  return {
    focus = focus or {},
    pre = pre or {},
    old = {},
    new = {},
    post = {},
  }
end

--- Returns list of Change objects parsed from the patch provided by LLMs
---@param patch string patch containing the changes
---@return Change[]
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
      -- only when the the next line uses @@ identifier
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

--- Returns list of Change objects parsed from the response provided by LLMs
---@param raw string raw text containing the patch with changes
---@return Change[]
function M.parse_changes(raw)
  local patches = {}
  for patch in raw:gmatch("%*%*%* Begin Patch%s+(.-)%s+%*%*%* End Patch") do
    table.insert(patches, patch)
  end
  if #patches == 0 then
    error("Invalid patch format: missing Begin/End markers")
  end

  local all_changes = {}
  for _, patch in ipairs(patches) do
    local changes = parse_changes_from_patch(patch)
    for _, change in ipairs(changes) do
      table.insert(all_changes, change)
    end
  end
  return all_changes
end

--- returns whether the given lines (needle) match the lines in the file we are editing at the given line number
---@param haystack string[] list of lines in the file we are updating
---@param pos number the line number where we are checking the match
---@param needle string[] list of lines we are trying to match
---@param opts? MatchOptions options for matching strategy
---@return boolean true of the given lines match at the given line number in haystack
local function matches_lines(haystack, pos, needle, opts)
  opts = opts or {}
  for i, needle_line in ipairs(needle) do
    local hayline = haystack[pos + i - 1]
    local is_same = hayline
      and ((hayline == needle_line) or (opts.trim_spaces and vim.trim(hayline) == vim.trim(needle_line)))
    if not is_same then
      return false
    end
  end
  return true
end

--- returns whether the given line number (before_pos) is after the focus lines
---@param lines string[] list of lines in the file we are updating
---@param before_pos number current line number before which the focus lines should appear
---@param opts? MatchOptions options for matching strategy
---@return boolean true of the given line number is after the focus lines
local function has_focus(lines, before_pos, focus, opts)
  opts = opts or {}
  local start = 1
  for _, focus_line in ipairs(focus) do
    local found = false
    for k = start, before_pos - 1 do
      if focus_line == lines[k] or (opts.trim_spaces and vim.trim(focus_line) == vim.trim(lines[k])) then
        start = k
        found = true
        break
      end
    end
    if not found then
      return false
    end
  end
  return true
end

--- returns new list of lines with the applied changes
---@param lines string[] list of lines in the file we are updating
---@param change Change change to be applied on the lines
---@param opts? MatchOptions options for matching strategy
---@return string[]|nil list of updated lines after change
function M.apply_change(lines, change, opts)
  opts = opts or {}
  for i = 1, #lines do
    local line_matches_change = (
      has_focus(lines, i, change.focus, opts)
      and matches_lines(lines, i - #change.pre, change.pre, opts)
      and matches_lines(lines, i, change.old, opts)
      and matches_lines(lines, i + #change.old, change.post, opts)
    )
    if line_matches_change then
      local new_lines = {}
      -- add lines before diff
      for k = 1, i - 1 do
        new_lines[#new_lines + 1] = lines[k]
      end
      -- add new lines
      local fix_spaces
      -- infer adjustment of spaces from the delete line
      if opts.trim_spaces and #change.old > 0 then
        if change.old[1] == " " .. lines[i] then
          -- diff patch added and extra space on left
          fix_spaces = function(ln)
            return ln:sub(2)
          end
        elseif #change.old[1] < #lines[i] then
          -- diff removed spaces on left
          local prefix = string.rep(" ", #lines[i] - #change.old[1])
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
      for k = i + #change.old, #lines do
        new_lines[#new_lines + 1] = lines[k]
      end
      return new_lines
    end
  end
end

return M
