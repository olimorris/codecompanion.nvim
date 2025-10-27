local files = require("codecompanion.utils.files")
local helpers = require("codecompanion.strategies.chat.tools.catalog.helpers")
local log = require("codecompanion.utils.log")

local fmt = string.format

---View the content of a file
---@param path string The file path to view
---@param view_range? [number, number] The range of lines to view (start_line, end_line)
local function view(path, view_range)
  local lines = files.read(path)
  if not lines then
    return { status = "error", data = "File not found" }
  end

  local start_line = view_range and view_range[1] or 1
  local end_line = view_range and view_range[2] or #lines

  local viewed_lines = {}
  for i = start_line, end_line do
    if lines[i] then
      table.insert(viewed_lines, lines[i])
    end
  end

  return { status = "success", data = table.concat(viewed_lines, "\n") }
end

---@class CodeCompanion.Tool.Memory: CodeCompanion.Tools.Tool
return {
  name = "memory",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.Memory
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      print(vim.inspect(args))
      local err
      if args.command == "view" then
        local ok, err = pcall(view, args.path, args.view_range)
      end

      if err then
        return { status = "error", data = err }
      end
      return { status = "success", data = "Command executed successfully" }
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
          command = {
            type = "string",
            description = "The command to execute on the client side.",
            enum = { "view", "create", "str_replace", "insert", "delete", "rename" },
          },
          path = {
            type = "string",
            description = "The relative path to the memory file.",
          },
          view_range = {
            type = "array",
            description = "The range of lines to view from the file. Format: [start_line, end_line]. For using the view command only.",
          },
          -- file_text = {}, -- Create only
          -- old_str = {}, -- str_replace only
          -- new_str = {}, -- str_replace only
          -- insert_line = {}, -- insert only
          -- insert_text = {}, -- insert only
          -- old_path = {}, -- rename only
          -- new_path = {}, -- rename only
        },
        required = {
          "command",
        },
      },
    },
  },
  handlers = {
    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools)
      log:trace("[Create File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@return nil|string
    prompt = function(self, tools)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      return fmt("Create a file at %s?", filepath)
    end,

    ---@param self CodeCompanion.Tool.CreateFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat
      local args = self.args
      local path = args.filepath

      local llm_output = fmt("<createFileTool>%s</createFileTool>", "Created file `%s` successfully")

      -- Get the file extension for syntax highlighting
      local file_ext = vim.fn.fnamemodify(path, ":e")

      local result_msg = fmt(
        [[Created file `%s`
```%s
%s
```]],
        path,
        file_ext,
        args.content or ""
      )

      chat:add_tool_output(self, llm_output, result_msg)
    end,

    ---@param self CodeCompanion.Tool.CreateFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local chat = tools.chat
      local args = self.args
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Create File Tool] Error output: %s", stderr)

      local error_output = fmt([[%s]], errors)
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.CreateFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param opts table
    ---@return nil
    rejected = function(self, tools, cmd, opts)
      local message = "The user rejected the creation of the file"
      opts = vim.tbl_extend("force", { message = message }, opts or {})
      helpers.rejected(self, tools, cmd, opts)
    end,
  },
}
