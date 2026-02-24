local cmd_tool = require("codecompanion.interactions.chat.tools.builtin.cmd_tool")
local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local fmt = string.format

---@class CodeCompanion.Tool.RunCommand: CodeCompanion.Tools.Tool
return cmd_tool({
  name = "run_command",
  description = "Run shell commands on the user's system, sharing the output with the user before then sharing with you.",
  schema = {
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
  },
  build_cmd = function(args)
    return args.cmd
  end,
  handlers = {
    ---@param self CodeCompanion.Tool.RunCommand
    ---@param meta { tools: CodeCompanion.Tools }
    setup = function(self, meta)
      local args = self.args

      local cmd = { cmd = vim.split(args.cmd, " ") }
      if args.flag then
        cmd.flag = args.flag
      end

      table.insert(self.cmds, cmd)
    end,
  },
  output = {
    ---Returns the command that will be executed
    ---@param self CodeCompanion.Tool.RunCommand
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, meta)
      return self.args.cmd
    end,

    ---@param self CodeCompanion.Tool.RunCommand
    ---@param meta {tools: CodeCompanion.Tools}
    ---@return string
    prompt = function(self, meta)
      return fmt("Run the command `%s`?", self.args.cmd)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.RunCommand
    ---@param meta {tools: CodeCompanion.Tools, cmd: string, opts: table}
    ---@return nil
    rejected = function(self, meta)
      local message = fmt("The user rejected the execution of the `%s` command", self.args.cmd)
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
})
