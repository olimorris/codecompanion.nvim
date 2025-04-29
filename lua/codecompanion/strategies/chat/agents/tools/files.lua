--[[
*Files Tool*
This tool can be used make edits to files on disk.
--]]

local Path = require("plenary.path")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local fmt = string.format
local file = nil

---Create a file and it's surrounding folders
---@param action table The action object
---@return nil
local function create(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:touch({ parents = true })
  p:write(action.contents or "", "w")
end

---Read the contents of af ile
---@param action table The action object
---@return table<string, string>
local function read(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  file = {
    content = p:read(),
    filetype = vim.fn.fnamemodify(p.filename, ":e"),
  }
  return file
end

---Read the contents of a file between specific lines
---@param action table The action object
---@return nil
local function read_lines(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  -- Read requested lines
  local extracted = {}
  local current_line = 0

  local lines = p:iter()

  -- Parse line numbers
  local start_line = tonumber(action.start_line) or 1
  local end_line = tonumber(action.end_line) or #lines

  for line in lines do
    current_line = current_line + 1
    if current_line >= start_line and current_line <= end_line then
      table.insert(extracted, current_line .. ":  " .. line)
    end
    if current_line > end_line then
      break
    end
  end

  file = {
    content = table.concat(extracted, "\n"),
    filetype = vim.fn.fnamemodify(p.filename, ":e"),
  }
  return file
end

---Edit the contents of a file
---@param action table The action object
---@return nil
local function edit(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local content = p:read()
  if not content then
    return util.notify(fmt("No data found in %s", action.path))
  end

  local changed, substitutions_count = content:gsub(vim.pesc(action.search), vim.pesc(action.replace))
  if substitutions_count == 0 then
    return util.notify(fmt("Could not find the search string in %s", action.path))
  end

  p:write(changed, "w")
end

---Delete a file
---@param action table The action object
---@return nil
local function delete(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:rm()
end

---Rename a file
---@param action table The action object
---@return nil
local function rename(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:rename({ new_name = new_p.filename })
end

---Copy a file
---@param action table The action object
---@return nil
local function copy(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:copy({ destination = new_p.filename, parents = true })
end

---Move a file
---@param action table The action object
---@return nil
local function move(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:copy({ destination = new_p.filename, parents = true })
  p:rm()
end

local actions = {
  create = create,
  read = read,
  read_lines = read_lines,
  edit = edit,
  delete = delete,
  rename = rename,
  copy = copy,
  move = move,
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
    ---@return nil|{ status: "success"|"error", data: string }
    function(self, args, input)
      local ok, _ = pcall(actions[args.action], args)
      if not ok then
        return { status = "error", data = "Could not run the Files tool" }
      end
      return { status = "success", data = "The tool ran successfully!" }
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "files",
      description = "Create/read/update/delete/rename/copy/move files on disk (user approval required)",
      parameters = {
        type = "object",
        properties = {
          action = {
            type = "string",
            enum = {
              "create",
              "read",
              "read_lines",
              "edit",
              "delete",
              "rename",
              "copy",
              "move",
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
            description = "Contents for create/edit; set to `null` otherwise.",
          },
          start_line = {
            anyOf = {
              { type = "integer" },
              { type = "null" },
            },
            description = "1‑based start line for read_lines; `null` otherwise.",
          },
          end_line = {
            anyOf = {
              { type = "integer" },
              { type = "null" },
            },
            description = "1‑based end line for read_lines; `null` otherwise.",
          },
          search = {
            anyOf = {
              { type = "string" },
              { type = "null" },
            },
            description = "Search pattern for edit; `null` otherwise.",
          },
          replace = {
            anyOf = {
              { type = "string" },
              { type = "null" },
            },
            description = "Replacement text for edit; `null` otherwise.",
          },
          new_path = {
            anyOf = {
              { type = "string" },
              { type = "null" },
            },
            description = "Destination path for rename/copy/move; `null` otherwise.",
          },
        },
        required = {
          "action",
          "path",
          "contents",
          "start_line",
          "end_line",
          "search",
          "replace",
          "new_path",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = [[# Files Tool (`files`)

## CONTEXT
- You are connected to a Neovim instance via CodeCompanion.
- You can create, read, read specific lines, edit, delete, rename, copy, or move files on disk.
- Every action requires explicit approval from the user.

## OBJECTIVE
- Only invoke this tool when the user explicitly requests a file operation.
- Do not perform any destructive actions without prior user confirmation.
- Return a single JSON-based function call matching the schema.

## RESPONSE
- Only invoke this tool when the user specifically asks.
- Use this tool strictly for file operations.

## POINTS TO NOTE
- This tool can be used alongside other tools within CodeCompanion
]],
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    ---@return nil
    on_exit = function(agent)
      log:debug("[Files Tool] on_exit handler executed")
      file = nil
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
        create = "Create a file at %s?",
        read = "Read %s?",
        read_lines = "Read specific lines in %s?",
        edit = "Edit %s?",
        delete = "Delete %s?",
        copy = "Copy %s?",
        rename = "Rename %s to %s?",
        move = "Move %s to %s?",
      }

      local args = self.args
      local path = vim.fn.fnamemodify(args.path, ":.")
      local action = string.lower(args.action)

      local new_path
      if args.new_path then
        new_path = vim.fn.fnamemodify(args.new_path, ":.")
      end

      if action == "rename" or action == "move" then
        table.insert(prompts, fmt(responses[action], path, new_path))
      else
        table.insert(prompts, fmt(responses[action], path))
      end

      return table.concat(prompts, "\n")
    end,

    ---@param self CodeCompanion.Tool.Files
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat

      local args = self.args
      chat:add_tool_output(
        self,
        fmt([[**Files Tool**: The %s action for `%s` was successful]], string.upper(args.action), args.path)
      )
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
