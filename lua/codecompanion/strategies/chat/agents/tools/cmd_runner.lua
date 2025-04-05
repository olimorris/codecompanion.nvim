local log = require("codecompanion.utils.log")
--[[
*Command Runner Tool*
This tool is used to run shell commands on your system
--]]

local config = require("codecompanion.config")
local util = require("codecompanion.utils")

---Outputs a message to the chat buffer that initiated the tool
---@param msg string The message to output
---@param agent CodeCompanion.Agent The tools object
---@param cmd table The command that was executed
---@param opts {cmd: table, output: table|string, message?: string}
local function to_chat(msg, agent, cmd, opts)
  local cmds = table.concat(cmd.cmd, " ")
  if opts and type(opts.output) == "table" then
    opts.output = vim.iter(opts.output):flatten():join("\n")
  end

  local content
  if opts.output == "" then
    content = string.format(
      [[%s the command `%s`.

]],
      msg,
      cmds
    )
  else
    content = string.format(
      [[%s the command `%s`:

```txt
%s
```

]],
      msg,
      cmds,
      opts.output
    )
  end

  return agent.chat:add_buf_message({
    role = config.constants.USER_ROLE,
    content = content,
  })
end

---@class CodeCompanion.Agent.Tool
return {
  name = "cmd_runner",
  cmds = {
    -- This is dynamically populated via the setup function
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "cmd_runner",
      description = "Run shell commands on the user's system, sharing the output with the user before then sharing with you.",
      parameters = {
        type = "object",
        properties = {
          cmd = {
            type = "string",
            description = "The command to run, e.g. `pytest` or `make test`",
          },
        },
        required = {
          "cmd",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = string.format(
    [[# Command Runner Tool (`cmd_runner`)

## CONTEXT
- You have access to a command runner tool running within CodeCompanion, in Neovim.
- You can use it to run shell commands on the user's system.
- You may be asked to run a specific command or to determine the appropriate command to fulfil the user's request.
- All tool executions take place in the current working directory %s.

## OBJECTIVE
- Follow the tool's schema.
- Respond with a single command, per tool execution.

## RESPONSE
- Only invoke this tool when the user specifically asks.
- If the user asks you to run a specific command, do so to the letter, paying great attention.
- Use this tool strictly for command execution; but file operations must NOT be executed in this tool unless the user explicitly approves.
- To run multiple commands, you will need to call this tool multiple times.

## SAFETY RESTRICTIONS
- Never execute the following dangerous commands under any circumstances:
  - `rm -rf /` or any variant targeting root directories
  - `rm -rf ~` or any command that could wipe out home directories
  - `rm -rf .` without specific context and explicit user confirmation
  - Any command with `:(){:|:&};:` or similar fork bombs
  - Any command that would expose sensitive information (keys, tokens, passwords)
  - Commands that intentionally create infinite loops
- For any destructive operation (delete, overwrite, etc.), always:
  1. Warn the user about potential consequences
  2. Request explicit confirmation before execution
  3. Suggest safer alternatives when available
- If unsure about a command's safety, decline to run it and explain your concerns

## USER ENVIRONMENT
- Shell: %s
- Operating System: %s
- Neovim Version: %s]],
    vim.fn.getcwd(),
    vim.o.shell,
    util.os(),
    vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
  ),
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    setup = function(agent)
      local tool = agent.tool --[[@type CodeCompanion.Agent.Tool]]
      local args = tool.args

      local cmd = { cmd = vim.split(args.cmd, " ") }
      if args.flag then
        cmd.flag = args.flag
      end

      table.insert(tool.cmds, cmd)
    end,
  },

  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param agent CodeCompanion.Agent
    ---@param self CodeCompanion.Agent.Tool
    ---@return string
    prompt = function(agent, self)
      return string.format("Run the command `%s`?", table.concat(self.cmds[1].cmd, " "))
    end,

    ---Rejection message back to the LLM
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@return nil
    rejected = function(agent, cmd)
      to_chat("I chose not to run", agent, cmd, { output = "" })
    end,

    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table
    ---@param stdout? table
    error = function(agent, cmd, stderr, stdout)
      to_chat("There was an error from", agent, cmd, { output = stderr })

      if stdout and not vim.tbl_isempty(stdout) then
        to_chat("There was also some output from", agent, cmd, { output = stdout })
      end
    end,

    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table
    success = function(agent, cmd, stdout)
      to_chat("The output from", agent, cmd, { output = stdout })
    end,
  },
}
