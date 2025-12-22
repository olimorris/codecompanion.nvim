local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Modify the path to be relative to the current working directory
---@param path string
---@return string
local function modify_path(path)
  return vim.fn.fnamemodify(path, ":.")
end

---Delete a file
---@param action {filepath: string} The action containing the filepath
---@return {status: "success"|"error", data: string}
local function delete(action)
  local filepath = vim.fs.joinpath(vim.fn.getcwd(), action.filepath)
  filepath = vim.fs.normalize(filepath)

  -- Check if file already exists
  local stat = vim.uv.fs_stat(filepath)
  if stat then
    if stat.type == "directory" then
      return {
        status = "error",
        data = fmt([[Failed deleting `%s` - As it's a directory]], action.filepath),
      }
    elseif stat.type == "file" then
      local success, err_msg = vim.uv.fs_unlink(filepath)
      if not success then
        return {
          status = "error",
          data = fmt([[Failed deleting `%s` - %s]], action.filepath, err_msg),
        }
      end
      return {
        status = "success",
        data = fmt([[Deleted `%s`]], action.filepath),
      }
    end
  end

  return {
    status = "error",
    data = fmt([[Failed deleting `%s` for an unknown reason]], action.filepath),
  }
end

---@class CodeCompanion.Tool.DeleteFile: CodeCompanion.Tools.Tool
return {
  name = "delete_file",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      return delete(args)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "delete_file",
      description = "This is a tool for deleting a file on the user's machine",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The relative path to the file to delete",
          },
        },
        required = {
          "filepath",
        },
      },
    },
  },
  handlers = {
    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools)
      log:trace("[Delete File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---Returns the command that will be executed
    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param args { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, args)
      return modify_path(self.args.filepath)
    end,

    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@return nil|string
    prompt = function(self, tools)
      return fmt("Delete the file at `%s`?", modify_path(self.args.filepath))
    end,

    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat
      local args = self.args
      local path = args.filepath

      chat:add_tool_output(self, fmt([[Deleted file `%s`]], path))
    end,

    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local chat = tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Delete File Tool] Error output: %s", stderr)

      local error_output = fmt([[%s]], errors)
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param opts table
    ---@return nil
    rejected = function(self, tools, cmd, opts)
      local message = "The user rejected the deletion of the file"
      opts = vim.tbl_extend("force", { message = message }, opts or {})
      helpers.rejected(self, tools, cmd, opts)
    end,
  },
}
