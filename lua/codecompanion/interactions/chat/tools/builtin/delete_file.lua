local files = require("codecompanion.utils.files")
local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Delete a file
---@param action {filepath: string} The action containing the filepath
---@return {status: "success"|"error", data: string}
local function delete(action)
  local filepath = vim.fs.normalize(action.filepath)

  if not files.is_path_within_cwd(filepath) then
    return {
      status = "error",
      data = fmt("Cannot delete `%s` - path is outside the current working directory", action.filepath),
    }
  end

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
            description = "The absolute path to the file to delete",
          },
        },
        required = {
          "filepath",
        },
      },
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    on_exit = function(self, meta)
      log:trace("[Delete File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---Returns the command that will be executed
    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param opts { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, opts)
      return self.args.filepath
    end,

    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil|string
    prompt = function(self, meta)
      return fmt("Delete the file at `%s`?", self.args.filepath)
    end,

    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param stdout table The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local args = self.args
      local path = args.filepath

      chat:add_tool_output(self, fmt([[Deleted file `%s`]], path))
    end,

    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Delete File Tool] Error output: %s", stderr)

      local error_output = fmt([[%s]], errors)
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.DeleteFile
    ---@param meta { tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      local message = "The user rejected the deletion of the file"
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
}
