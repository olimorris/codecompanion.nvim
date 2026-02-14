local Path = require("plenary.path")
local tool_helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Modify the path to be relative to the current working directory
---@param path string
---@return string
local function modify_path(path)
  return vim.fn.fnamemodify(path, ":.")
end

---Read the contents of a file
---@param action {filepath: string, start_line_number_base_zero: number, end_line_number_base_zero: number} The action containing the filepath
---@return {status: "success"|"error", data: string}
local function read(action)
  local path = file_utils.validate_and_normalize_path(action.filepath)
  local p = Path:new(path)
  if not p:exists() or not p:is_file() then
    return {
      status = "error",
      data = fmt("Error reading `%s`\nFile does not exist or is not a file", path),
    }
  end

  local lines = p:readlines()
  local start_line_zero = tonumber(action.start_line_number_base_zero)
  local end_line_zero = tonumber(action.end_line_number_base_zero)

  local error_msg = nil

  if not start_line_zero then
    error_msg = fmt(
      [[Error reading `%s`
start_line_number_base_zero must be a valid number, got: %s]],
      action.filepath,
      tostring(action.start_line_number_base_zero)
    )
  elseif not end_line_zero then
    error_msg = fmt(
      [[Error reading `%s`
end_line_number_base_zero must be a valid number, got: %s]],
      action.filepath,
      tostring(action.end_line_number_base_zero)
    )
  elseif start_line_zero < 0 then
    error_msg = fmt(
      [[Error reading `%s`
start_line_number_base_zero cannot be negative, got: %d"]],
      action.filepath,
      start_line_zero
    )
  elseif end_line_zero < -1 then
    error_msg = fmt(
      [[Error reading `%s`
end_line_number_base_zero cannot be less than -1, got: %d]],
      action.filepath,
      end_line_zero
    )
  elseif start_line_zero >= #lines then
    error_msg = fmt(
      [[Error reading `%s`
start_line_number_base_zero (%d) is beyond file length. File `%s` has %d lines (0-%d)]],
      action.filepath,
      start_line_zero,
      action.filepath,
      #lines,
      math.max(0, #lines - 1)
    )
  elseif end_line_zero ~= -1 and start_line_zero > end_line_zero then
    error_msg = fmt(
      [[Error reading `%s`
Invalid line range - start_line_number_base_zero (%d) comes after end_line_number_base_zero (%d)]],
      action.filepath,
      start_line_zero,
      end_line_zero
    )
  end

  if error_msg then
    return {
      status = "error",
      data = fmt([[%s]], error_msg),
    }
  end

  -- Clamp end_line_zero to the last valid line if it exceeds file length (unless -1)
  if not error_msg and end_line_zero ~= -1 and end_line_zero >= #lines then
    end_line_zero = math.max(0, #lines - 1)
  end

  -- Convert to 1-based indexing
  local start_line = start_line_zero + 1
  local end_line = end_line_zero == -1 and #lines or end_line_zero + 1

  -- Extract the specified lines
  local selected_lines = {}
  for i = start_line, end_line do
    table.insert(selected_lines, lines[i])
  end

  local content = table.concat(selected_lines, "\n")
  local file_ext = vim.fn.fnamemodify(p.filename, ":e")

  local output = fmt(
    [[Read file `%s` from line %d to %d:

````%s
%s
````]],
    action.filepath,
    action.start_line_number_base_zero,
    action.end_line_number_base_zero,
    file_ext,
    content
  )
  return {
    status = "success",
    data = output,
  }
end

---@class CodeCompanion.Tool.ReadFile: CodeCompanion.Tools.Tool
return {
  name = "read_file",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.ReadFile
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      return read(args)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "read_file",
      description = "Read the contents of a file.\n\nYou must specify the line range you're interested in. If the file contents returned are insufficient for your task, you may call this tool again to retrieve more content. You do not need to know the full path to run this file.",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The relative path to the file to read, including its filename and extension.",
          },
          start_line_number_base_zero = {
            type = "number",
            description = "The line number to start reading from, 0-based.",
          },
          end_line_number_base_zero = {
            type = "number",
            description = "The inclusive line number to end reading at, 0-based. Use -1 to read until the end of the file.",
          },
        },
        required = {
          "filepath",
          "start_line_number_base_zero",
          "end_line_number_base_zero",
        },
      },
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.ReadFile
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    on_exit = function(self, meta)
      log:trace("[Read File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---Returns the command that will be executed
    ---@param self CodeCompanion.Tool.ReadFile
    ---@param opts { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, opts)
      return modify_path(self.args.filepath)
    end,

    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil|string
    prompt = function(self, meta)
      return fmt("Read `%s`?", modify_path(self.args.filepath))
    end,

    ---@param self CodeCompanion.Tool.ReadFile
    ---@param stdout table The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local llm_output = vim.iter(stdout):flatten():join("\n")
      local start_line = self.args.start_line_number_base_zero
      local end_line = self.args.end_line_number_base_zero
      local range_text = end_line == -1 and fmt("(%d - end)", start_line) or fmt("(%d - %d)", start_line, end_line)
      chat:add_tool_output(self, llm_output, fmt("Read file `%s` %s", self.args.filepath, range_text))
    end,

    ---@param self CodeCompanion.Tool.ReadFile
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local args = self.args
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Read File Tool] Error output: %s", stderr)

      chat:add_tool_output(self, errors)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.ReadFile
    ---@param meta { tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      local message = "The user rejected the read file tool"
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      tool_helpers.rejected(self, meta)
    end,
  },
}
