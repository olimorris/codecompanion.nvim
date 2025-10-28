local files = require("codecompanion.utils.files")
local helpers = require("codecompanion.strategies.chat.tools.catalog.helpers")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Shows directory contents or file contents with optional line ranges
---@param path string The file path to view
---@param view_range? [number, number] The range of lines to view (start_line, end_line)
---@return string The content of the file within the specified range
local function view(path, view_range)
  local lines = files.read(path)
  if not lines then
    error(fmt("File not found or invalid path at `%s`", path))
  end

  local start_line = view_range and view_range[1] or 1
  local end_line = view_range and view_range[2] or #lines

  local viewed_lines = {}
  for i = start_line, end_line do
    if lines[i] then
      table.insert(viewed_lines, lines[i])
    end
  end

  return table.concat(viewed_lines, "\n")
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
      local function output_msg(status, msg)
        return { status = status, data = msg }
      end

      if args.command == "view" then
        local ok, output = pcall(view, args.path, args.view_range)
        if not ok then
          return output_msg("error", fmt("Error running the `view` command: ", output))
        end
        return output_msg("success", fmt("Content of `%s`:\n<memory>\n%s\n</memory>", args.path, output))
      end

      if args.command == "create" then
        local ok, output = pcall(create, args.path, args.view_range)
        if not ok then
          return output_msg("error", fmt("Error running the `create` command: ", output))
        end
        return output_msg("success", fmt("Created the file at %s", args.path))
      end
    end,
  },
  -- We don't need a schema as this is provided by Anthropic
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
