local Path = require("plenary.path")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class Action The arguments from the LLM's tool call
---@field filepath string The absolute path of the file to create
---@field content string The content to write to the file

---Create a file and it's surrounding folders
---@param action Action The arguments from the LLM's tool call
---@return string
local function create(action)
  local p = Path:new(action.filepath)
  p.filename = p:expand()
  p:touch({ parents = true })
  p:write(action.content or "", "w")
  return fmt("**Create File Tool**: `%s` was created successfully", action.filepath)
end

---@class CodeCompanion.Tool.CreateFile: CodeCompanion.Agent.Tool
return {
  name = "create_file",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.Editor The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      local ok, output = pcall(create, args)
      if not ok then
        return { status = "error", data = output }
      end
      return { status = "success", data = output }
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "create_file",
      description = "This is a tool for creating a new file on the user's machine. The file will be created with the specified content, creating any necessary parent directories.",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The absolute path to the file to create, including its filename and extension.",
          },
          content = {
            type = "string",
            description = "The content to write to the file.",
          },
        },
        required = {
          "filepath",
          "content",
        },
      },
    },
  },
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    ---@return nil
    on_exit = function(agent)
      log:debug("[Create File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Agent.Tool
    ---@param agent CodeCompanion.Agent
    ---@return nil|string
    prompt = function(self, agent)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      return fmt("Create a file at %s?", filepath)
    end,

    ---@param self CodeCompanion.Tool.Files
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local llm_output = vim.iter(stdout):flatten():join("\n")
      chat:add_tool_output(self, llm_output)
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
      log:debug("[Create File Tool] Error output: %s", stderr)

      local error_output = fmt(
        [[**Create File Tool**: Ran with an error:

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
      chat:add_tool_output(self, fmt("**Create File Tool**: The user declined to execute", self.args.action))
    end,
  },
}
