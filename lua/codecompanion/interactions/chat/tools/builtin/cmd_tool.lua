local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
local os_utils = require("codecompanion.utils.os")
local utils = require("codecompanion.utils")

local fmt = string.format

---Build the default system prompt for a command tool
---@param spec { name: string, description: string }
---@return string
local function default_system_prompt(spec)
  return fmt(
    [[# %s Tool (`%s`)

## CONTEXT
- You have access to the `%s` tool running within CodeCompanion, in Neovim.
- %s
- All tool executions take place in the current working directory %s.

## OBJECTIVE
- Follow the tool's schema.
- Respond with a single command, per tool execution.

## RESPONSE
- Only invoke this tool when the user specifically asks.

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
    spec.name,
    spec.name,
    spec.name,
    spec.description,
    vim.fn.getcwd(),
    vim.o.shell,
    utils.capitalize(os_utils.get_os()),
    vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
  )
end

---Create a command-line tool from a specification table.
---
---This factory function returns a complete CodeCompanion tool table that
---executes shell commands. Users provide a minimal spec and get a fully
---functional tool with schema, system prompt, approval prompts, and
---output handling.
---
---@param spec { name: string, description: string, schema: { properties: table, required: table, additionalProperties?: boolean }, build_cmd: fun(args: table): string, system_prompt?: string|fun(schema: table): string, handlers?: table, output?: table }
---@return CodeCompanion.Tools.Tool
local function cmd_tool(spec)
  -- Build the full schema envelope from the user's property spec
  local schema = {
    type = "function",
    ["function"] = {
      name = spec.name,
      description = spec.description,
      parameters = {
        type = "object",
        properties = spec.schema.properties,
        required = spec.schema.required,
        additionalProperties = spec.schema.additionalProperties or false,
      },
      strict = true,
    },
  }

  -- Default handlers
  local default_handlers = {
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools }
    setup = function(self, meta)
      local cmd_string = spec.build_cmd(self.args)
      local cmd = { cmd = vim.split(cmd_string, " ") }
      table.insert(self.cmds, cmd)
    end,
  }

  -- Default output handlers
  local default_output = {
    ---Returns the command that will be executed
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, meta)
      return spec.build_cmd(self.args)
    end,

    ---@param self CodeCompanion.Tools.Tool
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      if stderr then
        local chat = meta.tools.chat
        local cmd_string = spec.build_cmd(self.args)
        local errors = vim.iter(stderr):flatten():join("\n")

        local output = [[%s
```txt
%s
```]]

        local llm_output = fmt(output, fmt("There was an error running the `%s` command:", cmd_string), errors)
        local user_output = fmt(output, fmt("`%s` error", cmd_string), errors)

        chat:add_tool_output(self, llm_output, user_output)
      end
    end,

    ---Prompt the user to approve the execution of the command
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return string
    prompt = function(self, meta)
      return fmt("Run the command `%s`?", spec.build_cmd(self.args))
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      local message = fmt("The user rejected the execution of the `%s` tool", spec.name)
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,

    ---@param self CodeCompanion.Tools.Tool
    ---@param stdout table|nil The output from the tool
    ---@param meta { tools: table, cmd: table }
    ---@return nil
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      if stdout then
        local output = vim.iter(stdout[#stdout]):flatten():join("\n")
        local message = fmt(
          [[`%s`
````
%s
````]],
          spec.build_cmd(self.args),
          output
        )
        return chat:add_tool_output(self, message)
      end
      return chat:add_tool_output(self, fmt("There was no output from the %s tool", spec.name))
    end,
  }

  return {
    name = spec.name,
    cmds = {},
    schema = schema,
    system_prompt = spec.system_prompt or default_system_prompt(spec),
    handlers = vim.tbl_extend("force", default_handlers, spec.handlers or {}),
    output = vim.tbl_extend("force", default_output, spec.output or {}),
  }
end

return cmd_tool
