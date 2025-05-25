--[[
*Files Tool*
This tool can be used make edits to files on disk.
--]]

local Path = require("plenary.path")
local log = require("codecompanion.utils.log")
local patches = require("codecompanion.helpers.patches")

local fmt = string.format

PROMPT = [[# Files Tool (`files`)

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

]] .. patches.FORMAT_PROMPT .. [[

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
]]

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

---Edit the contents of a file
---@param action Action The arguments from the LLM's tool call
---@return string
local function update(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  -- 1. extract list of changes from the contents
  local raw = action.contents or ""
  local changes = patches.parse_changes(raw)

  -- 2. read file into lines
  local content = p:read()
  local lines = vim.split(content, "\n", { plain = true })

  -- 3. apply changes
  for _, change in ipairs(changes) do
    local new_lines = patches.apply_change(lines, change)
    if new_lines == nil then
      error(fmt("Diff block not found:\n\n%s\n\nNo changes were applied", patches.get_change_string(change)))
    else
      lines = new_lines
    end
  end

  -- 4. write back
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
  system_prompt = PROMPT,
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
