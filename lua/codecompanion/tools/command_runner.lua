local BaseTool = require("codecompanion.tools.base_tool")
local ctcr = require("codecompanion.tools.chunk")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.CommandRunnerTool : CodeCompanion.CopilotTool
local CommandRunnerTool = setmetatable({}, { __index = BaseTool })
CommandRunnerTool.__index = CommandRunnerTool

---@param copilot CodeCompanion.Copilot
function CommandRunnerTool.new(copilot)
  local self = setmetatable(BaseTool.new(copilot), CommandRunnerTool)
  self.name = "command_runner"
  return self
end

---@param args string A table containing the arguments necessary for execution.
---@param callback fun(chunk: CodeCompanion.CopilotToolChunkResp)
function CommandRunnerTool:execute(args, callback)
  local shell_command = string.format("sh -c '%s'", args:gsub("'", "'\\''"))
  local handle, err = io.popen(shell_command .. " 2>&1", "r")
  if not handle then
    callback(ctcr.new_error(self.copilot.bufnr, "\nError opening command: " .. err))
    return
  end

  local code
  local function close_handle()
    if handle then
      _, err, code = handle:close()
      handle = nil
    end
  end

  local ok, _ = pcall(function()
    for line in handle:lines() do
      callback(ctcr.new_progress(self.copilot.bufnr, line .. "\n"))
    end
  end)

  close_handle()

  if not ok then
    callback(ctcr.new_error(self.copilot.bufnr, "\nError during command execution: " .. tostring(err)))
  elseif code and code ~= 0 then
    callback(ctcr.new_final(self.copilot.bufnr, "\nCommand exited with code " .. tostring(code)))
  else
    callback(ctcr.new_final(self.copilot.bufnr, "\nCommand executed successfully."))
  end
end

function CommandRunnerTool:description()
  return "Executes shell commands and streams the output."
end

function CommandRunnerTool:input_format()
  return "A string containing the shell command to be executed."
end

function CommandRunnerTool:output_format()
  return "The output of the command."
end

function CommandRunnerTool:example()
  return [[
For the command_runner tool, you can execute shell commands to perform various operations. Here are several examples showcasing its usage:

1. List files in the current directory:
(command_runner)
```
ls -la
```
output:==
```

2. Search for a specific file pattern:
(command_runner)
```
find . -name "*.lua"
```
output:==
```

Important guidelines when using the command_runner tool:

1. Security: Never execute commands that could harm the user's system or expose sensitive information. Avoid commands that modify system settings or delete files unless explicitly requested and confirmed by the user.
2. File paths: When operating on files, prefer using relative paths from the current working directory. If absolute paths are necessary, ensure they are within the user's project directory.
3. Error handling: Be prepared to interpret and explain any error messages that may be returned by the command.
4. OS compatibility: Consider that commands may behave differently on various operating systems (Windows, macOS, Linux). When possible, use commands that are cross-platform compatible.
5. Permissions: Be aware that some commands may require elevated permissions. Inform the user if a command might need to be run with sudo or as an administrator.
6. Resource usage: For commands that might take a long time or use significant system resources, warn the user beforehand.
7. Output interpretation: After running a command, be prepared to explain its output to the user if it's not self-explanatory.
8. Chaining commands: You can use shell operators to chain multiple commands if necessary, e.g., "command1 && command2" to run command2 only if command1 succeeds.
Remember, the output of the command will be returned automatically. Do not attempt to fabricate or write the output yourself. Always wait for the actual result of the command execution before proceeding with your response.

Adjust the commands according to the specific task at hand and the user's needs. Always prioritize safety and explain the purpose of the command before executing it.
  ]]
end

return CommandRunnerTool
