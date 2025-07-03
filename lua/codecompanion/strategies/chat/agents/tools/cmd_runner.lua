--[[
  *Command Runner Tool*
  This tool is used to run shell commands on your system
--]]
local util = require("codecompanion.utils")

local fmt = string.format

---@class CodeCompanion.Tool.CmdRunner: CodeCompanion.Agent.Tool
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
          flag = {
            anyOf = {
              { type = "string" },
              { type = "null" },
            },
            description = 'If running tests, set to `"testing"`; null otherwise',
          },
        },
        required = {
          "cmd",
          "flag",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = fmt(
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

## POINTS TO NOTE
- This tool can be used alongside other tools within CodeCompanion

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
    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param agent CodeCompanion.Agent The tool object
    setup = function(self, agent)
      local args = self.args

      local cmd = { cmd = vim.split(args.cmd, " ") }
      if args.flag then
        cmd.flag = args.flag
      end

      table.insert(self.cmds, cmd)
    end,
  },

  output = {
    ---Prompt the user to approve the execution of the command
    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param agent CodeCompanion.Agent
    ---@return string
    prompt = function(self, agent)
      return fmt("Run the command `%s`?", table.concat(self.cmds[1].cmd, " "))
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@return nil
    rejected = function(self, agent, cmd)
      agent.chat:add_tool_output(
        self,
        fmt("The user rejected the execution of the command `%s`?", table.concat(self.cmds[1].cmd, " "))
      )
    end,

    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      local chat = agent.chat
      local cmds = table.concat(cmd.cmd, " ")
      local errors = vim.iter(stderr):flatten():join("\n")

      local output = [[%s
```txt
%s
```]]

      local llm_output = fmt(output, fmt("There was an error running the `%s` command:", cmds), errors)
      local user_output = fmt(output, fmt("`%s` error", cmds), errors)

      chat:add_tool_output(self, llm_output, user_output)

      if stdout and not vim.tbl_isempty(stdout) then
        stdout = vim.iter(stdout):flatten():join("\n")
        output = [[%s
```txt
%s
```]]

        llm_output = fmt(output, fmt("There was also some output from the `%s` command:", cmds), stdout)
        user_output = fmt(output, fmt("`%s`", cmds), stdout)

        chat:add_tool_output(self, llm_output, user_output)
      end
    end,

    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      if stdout and vim.tbl_isempty(stdout) then
        return chat:add_tool_output(self, "There was no output from the cmd_runner tool")
      end
      local output = vim.iter(stdout[#stdout]):flatten():join("\n")
      local message = fmt(
        [[`%s`
```
%s
```]],
        table.concat(cmd.cmd, " "),
        output
      )
      chat:add_tool_output(self, message)
    end,
  },
}
