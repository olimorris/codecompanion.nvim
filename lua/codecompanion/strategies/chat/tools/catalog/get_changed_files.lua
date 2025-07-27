local Job = require("plenary.job")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@param state string
---@return string[]|nil, string|nil
local function get_git_diff(state, opts)
  local cmd, desc
  if state == "staged" then
    cmd = { "git", "diff", "--cached" }
    desc = "staged"
  elseif state == "unstaged" then
    cmd = { "git", "diff" }
    desc = "unstaged"
  elseif state == "merge-conflicts" then
    cmd = { "git", "diff", "--name-only", "--diff-filter=U" }
    desc = "merge-conflicts"
  else
    return nil, nil
  end

  local ok, result = pcall(function()
    return Job:new({ command = cmd[1], args = vim.list_slice(cmd, 2), cwd = vim.fn.getcwd() }):sync()
  end)
  if not ok then
    return nil, desc
  end

  if result and #result > opts.max_lines then
    result = vim.list_slice(result, 1, opts.max_lines)
    table.insert(result, "... (diff output truncated)")
  end

  return result, desc
end

---Get changed files in the current working directory based on the git state.
---@param action {source_control_state?: string[]}
---@param opts {max_lines: number}
---@return {status: "success"|"error", data: string}
local function get_changed_files(action, opts)
  local states = action.source_control_state or { "unstaged", "staged", "merge-conflicts" }
  local output = {}

  for _, state in ipairs(states) do
    local result, desc = get_git_diff(state, opts)
    if desc then
      if state == "merge-conflicts" then
        if result and #result > 0 then
          table.insert(
            output,
            fmt(
              [[<getChangedFiles type="%s">
- %s
</getChangedFiles]],
              desc,
              table.concat(result, "\n- ")
            )
          )
        end
      else
        if result and #result > 0 then
          table.insert(
            output,
            fmt(
              [[<getChangedFiles type="%s">
```diff
%s
```
</getChangedFiles>]],
              desc,
              table.concat(result, "\n")
            )
          )
        end
      end
    end
  end

  if vim.tbl_isempty(output) then
    return {
      status = "success",
      data = "No changed files found.",
    }
  end

  return {
    status = "success",
    data = table.concat(output, "\n\n"),
  }
end

---@class CodeCompanion.Tool.GetChangedFiles: CodeCompanion.Tools.Tool
return {
  name = "get_changed_files",
  cmds = {
    ---@param self CodeCompanion.Tool.GetChangedFiles
    ---@param args table
    ---@param input? any
    function(self, args, input)
      return get_changed_files(args, self.tool.opts)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "get_changed_files",
      description = "Get git diffs of current file changes in the current working directory.",
      parameters = {
        type = "object",
        properties = {
          source_control_state = {
            type = "array",
            items = {
              type = "string",
              enum = { "staged", "unstaged", "merge-conflicts" },
            },
            description = "The kinds of git state to filter by. Allowed values are: 'staged', 'unstaged', and 'merge-conflicts'. If not provided, all states will be included.",
          },
        },
      },
    },
  },
  handlers = {
    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools)
      log:trace("[Insert Edit Into File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.GetChangedFiles
    ---@param tools CodeCompanion.Tools
    prompt = function(self, tools)
      return "Get changed files in the git repository?"
    end,

    ---@param self CodeCompanion.Tool.GetChangedFiles
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat
      local output = vim.iter(stdout):flatten():join("\n")
      chat:add_tool_output(self, output, "Reading changed files")
    end,

    ---@param self CodeCompanion.Tool.GetChangedFiles
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local chat = tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      chat:add_tool_output(self, errors)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.GetChangedFiles
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@return nil
    rejected = function(self, tools, cmd)
      local chat = tools.chat
      chat:add_tool_output(self, "The user declined to get changed files")
    end,
  },
}
