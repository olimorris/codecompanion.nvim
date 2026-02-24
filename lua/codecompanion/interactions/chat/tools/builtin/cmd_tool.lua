local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local fmt = string.format

---Create a command-line tool from a specification table.
---
---This factory function returns a complete CodeCompanion tool table that
---executes shell commands. Users provide a minimal spec and get a fully
---functional tool with schema, approval prompts, and output handling.
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
    system_prompt = spec.system_prompt,
    handlers = vim.tbl_extend("force", default_handlers, spec.handlers or {}),
    output = vim.tbl_extend("force", default_output, spec.output or {}),
  }
end

return cmd_tool
