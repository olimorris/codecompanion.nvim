local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Create a file and the surrounding folders
---@param action {filepath: string, content: string} The action containing the filepath and content
---@return {status: "success"|"error", data: string}
local function create(action)
  local filepath = vim.fs.joinpath(vim.fn.getcwd(), action.filepath)
  filepath = vim.fs.normalize(filepath)

  -- Check if file already exists
  local stat = vim.uv.fs_stat(filepath)
  if stat then
    if stat.type == "directory" then
      return {
        status = "error",
        data = fmt(
          [[Failed creating `%s`
- Already exists as a directory]],
          action.filepath
        ),
      }
    elseif stat.type == "file" then
      return {
        status = "error",
        data = fmt(
          [[Failed creating `%s`
- File already exists]],
          action.filepath
        ),
      }
    end
  end

  local parent_dir = vim.fs.dirname(filepath)

  -- Ensure parent directory exists
  if not vim.uv.fs_stat(parent_dir) then
    local success, err_msg = files.create_dir_recursive(parent_dir)
    if not success then
      local error_message = fmt(
        [[Failed creating `%s`
- %s]],
        action.filepath,
        err_msg
      )
      log:error(error_message)
      return { status = "error", data = error_message }
    end
  end

  -- Create file with safer error handling
  local fd, fs_open_err, fs_open_errname = vim.uv.fs_open(filepath, "w", 420) -- 0644 permissions
  if not fd then
    local error_message = fmt(
      [[Failed creating `%s`
- %s
-%s ]],
      action.filepath,
      fs_open_err,
      fs_open_errname
    )
    log:error(error_message)
    return { status = "error", data = error_message }
  end

  -- Try to write to the file
  local bytes_written, fs_write_err, fs_write_errname = vim.uv.fs_write(fd, action.content)
  local write_error_message
  if not bytes_written then
    write_error_message = fmt(
      [[Failed creating `%s`
- %s]],
      action.filepath,
      fs_write_err
    )
  elseif bytes_written ~= #action.content then
    write_error_message = fmt(
      [[Failed creating `%s`
- Could only write %s bytes]],
      action.filepath,
      bytes_written
    )
  end

  -- Always try to close the file descriptor
  local close_success, fs_close_err, fs_close_errname = vim.uv.fs_close(fd)
  local close_error_message
  if not close_success then
    close_error_message = fmt(
      [[Failed creating `%s`
- Could not close the file
- %s ]],
      action.filepath,
      fs_close_err
    )
  end

  -- Combine errors if any
  local final_error_message
  if write_error_message and close_error_message then
    final_error_message = write_error_message .. ". Additionally, " .. close_error_message
  elseif write_error_message then
    final_error_message = write_error_message
  elseif close_error_message then
    final_error_message = close_error_message
  end

  -- If any error occurred during write or close, return error
  if final_error_message then
    local full_error = fmt(
      [[Failed creating `%s`
- %s]],
      action.filepath,
      final_error_message
    )
    log:error(full_error)
    return { status = "error", data = full_error }
  end

  -- If we reach here, all operations (open, write, close) were successful
  return {
    status = "success",
    data = fmt([[Created `%s`]], action.filepath),
  }
end

---@class CodeCompanion.Tool.CreateFile: CodeCompanion.Agent.Tool
return {
  name = "create_file",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.CreateFile
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      return create(args)
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
            description = "The relative path to the file to create, including its filename and extension.",
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
      log:trace("[Create File Tool] on_exit handler executed")
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

    ---@param self CodeCompanion.Tool.CreateFile
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local output = vim.iter(stdout):flatten():join("\n")
      local args = self.args
      local filepath = args.filepath

      local llm_output = fmt("<createFileTool>%s</createFileTool>", "Created file `%s` successfully")

      -- Get the file extension for syntax highlighting
      local file_ext = vim.fn.fnamemodify(filepath, ":e")

      local result_msg = fmt(
        [[Created file `%s`
```%s
%s
```]],
        filepath,
        file_ext,
        args.content or ""
      )

      chat:add_tool_output(self, llm_output, result_msg)
    end,

    ---@param self CodeCompanion.Tool.CreateFile
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      local chat = agent.chat
      local args = self.args
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Create File Tool] Error output: %s", stderr)

      local error_output = fmt([[%s]], errors)
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.CreateFile
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@return nil
    rejected = function(self, agent, cmd)
      local chat = agent.chat
      chat:add_tool_output(self, "User rejected the creation of the file")
    end,
  },
}
