--[[
*Files Tool*
This tool can be used make edits to files on disk.
--]]

local Path = require("plenary.path")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class Action The arguments from the LLM's tool call
---@field action string CREATE / READ / UPDATE / DELETE action to perform
---@field path string path of the file to perform action on
---@field contents string diff in case of UPDATE; raw contents in case of CREATE

---Create a file and it's surrounding folders
---@param action Action The arguments from the LLM's tool call
---@return string
local function create(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:touch({ parents = true })
  p:write(action.contents or "", "w")
  return fmt("The CREATE action for `%s` was successful", action.path)
end

---Read the contents of file
---@param action Action The arguments from the LLM's tool call
---@return string
local function read(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local output = fmt(
    [[The file's contents are:

```%s
%s
```]],
    vim.fn.fnamemodify(p.filename, ":e"),
    p:read()
  )
  return output
end

---@class Change
---@field focus table list of lines before changes for larger context
---@field pre table list of unchanged lines just before edits
---@field old table list of lines to be removed
---@field new table list of lines to be added
---@field post table list of unchanged lines just after edits
--- Returns an new (empty) change table instance
---@param focus table list of focus lines, used to create a new change set with similar focus
---@param pre table list of pre lines to extend an existing change set
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
---@param patch string patch contents to be parsed
---@return Change[]
local function parse_changes(patch)
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

---@class MatchOptions
---@field trim_spaces boolean trim spaces while comparing lines
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
local function apply_change(lines, change, opts)
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

---Edit the contents of a file
---@param action Action The arguments from the LLM's tool call
---@return string
local function update(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  -- 1. extract raw patch
  local raw = action.contents or ""
  local patch = raw:match("%*%*%* Begin Patch%s+(.-)%s+%*%*%* End Patch")
  if not patch then
    error("Invalid patch format: missing Begin/End markers")
  end

  -- 2. read file into lines
  local content = p:read()
  local lines = vim.split(content, "\n", { plain = true })

  -- 3. parse changes
  local changes = parse_changes(patch)

  -- 4. apply changes
  for _, change in ipairs(changes) do
    local new_lines = apply_change(lines, change)
    if new_lines == nil then
      -- try applying patch in flexible spaces mode
      -- there is no standardised way to of spaces in diffs
      -- python differ specifies a single space after +/-
      -- while gnu udiff uses no spaces
      --
      -- and LLM models (especially Claude) sometimes strip
      -- long spaces on the left in case of large nestings (eg html)
      -- trim_spaces mode solves all of these
      new_lines = apply_change(lines, change, { trim_spaces = true })
    end
    if new_lines == nil then
      error(fmt("Diff block not found:\n\n%s", patch))
    else
      lines = new_lines
    end
  end

  -- 5. write back
  p:write(table.concat(lines, "\n"), "w")
  return fmt("The UPDATE action for `%s` was successful", action.path)
end

---Delete a file
---@param action table The arguments from the LLM's tool call
---@return string
local function delete(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:rm()
  return fmt("The DELETE action for `%s` was successful", action.path)
end

local actions = {
  CREATE = create,
  READ = read,
  UPDATE = update,
  DELETE = delete,
}

---@class CodeCompanion.Tool.Files: CodeCompanion.Agent.Tool
return {
  name = "files",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.Editor The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      args.action = args.action and string.upper(args.action)
      if not actions[args.action] then
        return { status = "error", data = fmt("Unknown action: %s", args.action) }
      end
      local ok, outcome = pcall(actions[args.action], args)
      if not ok then
        return { status = "error", data = outcome }
      end
      return { status = "success", data = outcome }
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "files",
      description = "CREATE/READ/UPDATE/DELETE files on disk (user approval required)",
      parameters = {
        type = "object",
        properties = {
          action = {
            type = "string",
            enum = {
              "CREATE",
              "READ",
              "UPDATE",
              "DELETE",
            },
            description = "Type of file action to perform.",
          },
          path = {
            type = "string",
            description = "Path of the target file.",
          },
          contents = {
            anyOf = {
              { type = "string" },
              { type = "null" },
            },
            description = "Contents of new file in the case of CREATE action; patch in the specified format for UPDATE action. `null` in the case of READ or DELETE actions.",
          },
        },
        required = {
          "action",
          "path",
          "contents",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = [[# Files Tool (`files`)

- This tool is connected to the Neovim instance via CodeCompanion.
- Use this tool to CREATE / READ / UPDATE or DELETE files.
- You do not need to ask for permission to use this tool to perform CRUD actions. CodeCompanion will ask for those permissions automatically while executing the actions.

## Instructions for Usage

- You must provide the `action`, `path` and `contents` to use this tool.
- The `action` can be one of `CREATE`, `READ`, `UPDATE`, or `DELETE`.
- The `path` must be a relative path. It should NEVER BE AN ABSOLUTE PATH.
- The `contents` should be `null` for the `READ` action. Use the `READ` action to read the contents of a file.
- The `contents` should be `null` for the `DELETE` action. Use the `DELETE` action to remove any file.
- The `contents` will be the actual contents to write in the file in case of the `CREATE` action. Use the `CREATE` action to create a new file.
- The `contents` must be in the diff format given below in the case of the `UPDATE` action. Use the `UPDATE` action to make changes to an existing file.

### Format of `contents` for the `UPDATE` action

The format of diff and `contents` in `UPDATE` action is a bit different. Pay a close attention to the following details for its implementation.

The `contents` of the `UPDATE` action must be in this format:

*** Begin Patch
[PATCH]
*** End Patch

The `[PATCH]` is the series of diffs to be applied for each change in the file. Each diff should be in this format:

[3 lines of pre-context]
-[old code]
+[new code]
[3 lines of post-context]

The context blocks are 3 lines of existing code, immediately before and after the modified lines of code. Lines to be modified should be prefixed with a `+` or `-` sign. Unchanged lines used for context starting with a `-` (such as comments in Lua) can be prefixed with a space ` `.

Multiple blocks of diffs should be separated by an empty line and `@@[identifier]` detailed below.

The linked context lines next to the edits are enough to locate the lines to edit. DO NOT USE line numbers anywhere in the contents.

You can use `@@[identifier]` to define a larger context in case the immediately before and after context is not sufficient to locate the edits. Example:

@@class BaseClass(models.Model):
[3 lines of pre-context]
-	pass
+	raise NotImplementedError()
[3 lines of post-context]

You can also use multiple `@@[identifiers]` to provide the right context if a single `@@` is not sufficient.

Example of `contents` with multiple blocks of changes and `@@` identifiers:

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

## Examples

These are few complete examples of the responses from this tool:

```
// CREATE
{
  "action": "CREATE",
  "path": "src/main.py",
  "contents": "print('Hello')\n"
}

// READ
{
  "action": "READ",
  "path": "src/main.py",
  "contents": null
}

// UPDATE
{
  "action": "UPDATE",
  "path": "src/main.py",
  "contents": "*** Begin Patch\n@@def greet():\n-    pass\n+    print('Hello')\n*** End Patch"
}

// DELETE
{
  "action": "DELETE",
  "path": "src/main.py",
  "contents": null
}
```
]],
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    ---@return nil
    on_exit = function(agent)
      log:debug("[Files Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Agent.Tool
    ---@param agent CodeCompanion.Agent
    ---@return nil|string
    prompt = function(self, agent)
      local responses = {
        CREATE = "Create a file at %s?",
        READ = "Read %s?",
        UPDATE = "Edit %s?",
        DELETE = "Delete %s?",
      }

      local args = self.args
      local path = vim.fn.fnamemodify(args.path, ":.")
      local action = args.action

      if action and path and responses[string.upper(action)] then
        return fmt(responses[string.upper(action)], path)
      end
    end,

    ---@param self CodeCompanion.Tool.Files
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local args = self.args
      local llm_output = vim.iter(stdout):flatten():join("\n")
      local user_output = fmt([[**Files Tool**: The %s action for `%s` was successful]], args.action, args.path)
      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.Files
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      local chat = agent.chat
      local args = self.args
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Files Tool] Error output: %s", stderr)

      local error_output = fmt(
        [[**Files Tool**: There was an error running the %s action:

```txt
%s
```]],
        args.action,
        errors
      )
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.Files
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@return nil
    rejected = function(self, agent, cmd)
      local chat = agent.chat
      chat:add_tool_output(self, fmt("**Files Tool**: The user declined to run the `%s` action", self.args.action))
    end,
  },
}
