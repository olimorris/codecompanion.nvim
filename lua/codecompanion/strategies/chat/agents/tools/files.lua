--[[
*Files Tool*
This tool can be used make edits to files on disk.
--]]

local Path = require("plenary.path")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local fmt = string.format

---Create a file and it's surrounding folders
---@param action table The action object
---@return nil
local function create(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:touch({ parents = true })
  p:write(action.contents or "", "w")
end

---Read the contents of file
---@param action table The action object
---@return string
local function read(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local output = fmt([[The file's contents are:

```%s
%s
```]], vim.fn.fnamemodify(p.filename, ":e"), p.read())
  return output
end

local function parseBlock(block)
  local focus, pre, old, new, post = {}, {}, {}, {}, {}
  local phase = "focus_pre"
  for _, line in ipairs(vim.split(block, "\n", { plain = true })) do
    if phase == "focus_pre" and vim.startswith(line, "@@") then
      local ref = vim.trim(line:sub(3))
      if ref and #ref > 0 then
        focus[#focus + 1] = ref
      end
    elseif phase == "focus_pre" and line:sub(1, 1) == "-" then
      phase = "hunk"
      old[#old + 1] = line:sub(2)
    elseif phase == "focus_pre" and line:sub(1, 1) == "+" then
      phase = "hunk"
      new[#new + 1] = line:sub(2)
    elseif phase == "focus_pre" then
      pre[#pre + 1] = line
    elseif phase == "hunk" and line:sub(1, 1) == "-" then
      old[#old + 1] = line:sub(2)
    elseif phase == "hunk" and line:sub(1, 1) == "+" then
      new[#new + 1] = line:sub(2)
    elseif phase == "hunk" then
      post[#post + 1] = line
    end
  end
  return {
    focus = focus,
    pre = pre,
    old = old,
    new = new,
    post = post
  }
end

local function matchesLines(haystack, pos, needle)
  for i, needleLine in ipairs(needle) do
    if haystack[pos + i - 1] ~= needleLine then
      return false
    end
  end
  return true
end

local function hasFocus(lines, beforePos, focus)
  local start = 1
  for _, line in ipairs(focus) do
    local found = false
    for k = start, beforePos - 1 do
      if lines[k] == line then
        start = k
        found = true
        break
      end
    end
    if not found then return false end
  end
  return true
end

local function applyChange(lines, change)
  for i = 1, #lines do
    if hasFocus(lines, i, change.focus) and matchesLines(lines, i - #change.pre, change.pre) and matchesLines(lines, i, change.old) and matchesLines(lines, i + #change.old, change.post) then
      local new_lines = {}
      -- before diff
      for k = 1, i - 1 do
        new_lines[#new_lines + 1] = lines[k]
      end
      -- new lines
      for _, ln in ipairs(change.new) do
        new_lines[#new_lines + 1] = ln
      end
      -- remaining lines
      for k = i + #change.old, #lines do
        new_lines[#new_lines + 1] = lines[k]
      end
      return new_lines
    end
  end
end

---Edit the contents of a file
---@param action table The action object
---@return nil
local function update(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  -- 1. extract raw patch
  local raw = action.contents or ""
  local patch = raw:match("^%*%*%* Begin Patch%s*(.-)%s*%*%*%* End Patch$")
  if not patch then
    error("Invalid patch format: missing Begin/End markers")
  end

  -- 2. read file into lines
  local content = p:read()
  local lines = vim.split(content, "\n", { plain = true })

  -- 3. split into blocks
  local blocks = vim.split(patch, "\n\n", { plain = true })
  for _, blk in ipairs(blocks) do
    -- 4. parse changes
    local change = parseBlock(blk)
    -- 5. apply changes
    local new_lines = applyChange(lines, change)
    if new_lines == nil then
      error(fmt("Diff block not found:\n\n%s", blk))
    else
      lines = new_lines
    end
  end

  -- 6. write back
  p:write(table.concat(lines, "\n"), "w")
end

---Delete a file
---@param action table The action object
---@return nil
local function delete(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:rm()
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
  actions = actions,
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.Editor The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      local ok, data = pcall(actions[string.upper(args.action)], args)
      if not ok then
        return { status = "error", data = data }
      end
      return { status = "success", data = data }
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
            description = "Type of file operation to perform.",
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
            description =
            "Contents of new file in the case of CREATE action. V4A diff-patch in case of UPDATE action. `null` in case of READ or DELETE.",
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

## Context

- You are connected to a Neovim instance via CodeCompanion.
- Use this `files` tool to CREATE / READ / UPDATE or DELETE a file.
- CodeCompanion asks the user for approval before this tool executes, so you do not need to ask for permission.

## Instructions

- You can use this tool to create new files, read existing files, update files, or delete some files.
- The `path` references should always only be relative, NEVER ABSOLUTE.
- In the case of `READ` or `DELETE` actions, the `contents` should be `null`.
- In the case of the `CREATE` action, the `contents` will be placed as it is in the new file.
- In the case of the `UPDATE` action, the `contents` should be in the V4A diff format as detailed below.

### Diff format of `contents` for `UPDATE` action

The `UPDATE` action effectively allows you to execute a diff/patch against a file. The format of the diff specification is unique to this task, so pay careful attention to these instructions. To use the `UPDATE` action, you should pass a message of the following structure as "contents":

*** Begin Patch
[YOUR_PATCH]
*** End Patch

Where [YOUR_PATCH] is the actual content of your patch, specified in the following V4A diff format.

For each snippet of code that needs to be changed, repeat the following:
[context_before] -> See below for further instructions on context.
- [old_code] -> Precede the old code with a minus sign.
+ [new_code] -> Precede the new, replacement code with a plus sign.
[context_after] -> See below for further instructions on context.

For instructions on [context_before] and [context_after]:
- By default, show 3 lines of code immediately above and 3 lines immediately below each change. If a change is within 3 lines of a previous change, do NOT duplicate the first change's [context_after] lines in the second change's [context_before] lines.
- If 3 lines of context is insufficient to uniquely identify the snippet of code within the file, use the @@ operator to indicate the class or function to which the snippet belongs. For instance, we might have:
@@ class BaseClass
[3 lines of pre-context]
- [old_code]
+ [new_code]
[3 lines of post-context]

- If a code block is repeated so many times in a class or function such that even a single @@ statement and 3 lines of context cannot uniquely identify the snippet of code, you can use multiple `@@` statements to jump to the right context. For instance:

@@ class BaseClass
@@ 	def method():
[3 lines of pre-context]
- [old_code]
+ [new_code]
[3 lines of post-context]

NOTE: We DO NOT use line numbers in this diff format, as the context is enough to uniquely identify code. An example of a message that you might pass as "input" to this function, in order to apply a patch, is shown below.

*** Begin Patch
@@ class BaseClass
@@     def search():
-        pass
+        raise NotImplementedError()

@@ class Subclass
@@     def search():
-        pass
+        raise NotImplementedError()

*** End Patch

- This tool can be used alongside other tools within CodeCompanion.
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
    ---@return string
    prompt = function(self, agent)
      local prompts = {}

      local responses = {
        CREATE = "Create a file at %s?",
        READ = "Read %s?",
        UPDATE = "Edit %s?",
        DELETE = "Delete %s?",
      }

      local args = self.args
      local path = vim.fn.fnamemodify(args.path, ":.")
      local action = string.upper(args.action)

      table.insert(prompts, fmt(responses[action], path))
      return table.concat(prompts, "\n")
    end,

    ---@param self CodeCompanion.Tool.Files
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local args = self.args
      local llm_output = vim.iter(stdout):flatten():join("\n")
      local user_output =
          fmt([[**Files Tool**: The %s action for `%s` was successful]], string.upper(args.action), args.path)
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
        [[**Files Tool**: There was an error running the %s command:

```txt
%s
```]],
        string.upper(args.action),
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
