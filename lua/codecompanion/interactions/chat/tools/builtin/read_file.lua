local tool_helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local fmt = string.format

---Build the tool's error output
---@param filepath string
---@param message string
---@return {status: "error", data: string}
local function read_error(filepath, message)
  return {
    status = "error",
    data = fmt("Error reading `%s`\n%s", filepath, message),
  }
end

---Normalize an optional line bound, where absent and negative both mean the default
---@param value any
---@param default integer
---@param name string
---@return integer? line
---@return string? error_message
local function normalize_bound(value, default, name)
  if value == nil or value == vim.NIL or value == "" then
    return default
  end

  local line = tonumber(value)
  if not line or line % 1 ~= 0 then
    return nil, fmt("%s must be a valid integer, got: %s", name, tostring(value))
  end

  return line < 0 and default or line
end

---Resolve and validate the effective, zero-based line range
---@param args {start_line: any, end_line: any, line_count: integer}
---@return {start_line: integer, end_line: integer}? range
---@return string? error_message
local function resolve_range(args)
  local last_line = args.line_count - 1

  local start_line, start_error = normalize_bound(args.start_line, 0, "start_line")
  if start_error then
    return nil, start_error
  end
  if start_line > last_line then
    return nil, fmt("start_line (%d) is beyond the file's last line (%d)", start_line, last_line)
  end

  local end_line, end_error = normalize_bound(args.end_line, last_line, "end_line")
  if end_error then
    return nil, end_error
  end

  end_line = math.min(end_line, last_line)
  if start_line > end_line then
    return nil, fmt("start_line (%d) comes after end_line (%d)", start_line, end_line)
  end

  return { start_line = start_line, end_line = end_line }
end

---Format a zero-based line range
---@param range {start_line: integer, end_line: integer}
---@return string
local function format_range(range)
  return fmt("%d - %d", range.start_line, range.end_line)
end

---Split normalized content without treating a trailing newline as another line
---@param content string
---@return string[]
local function split_lines(content)
  content = file_utils.normalize_content(content)
  local lines = vim.split(content, "\n")
  if content:sub(-1) == "\n" then
    table.remove(lines)
  end
  return lines
end

---Slice the requested line range out of a file's contents
---@param request table The arguments from the LLM's tool call
---@param lines string[] Every line in the file
---@return {status: "success", data: {for_llm: string, for_user: string}}|{status: "error", data: string} result
local function extract_range(request, lines)
  local range, error_message = resolve_range({
    start_line = request.start_line,
    end_line = request.end_line,
    line_count = #lines,
  })
  if not range then
    return read_error(request.filepath, error_message)
  end

  local range_label = format_range(range)
  local content = table.concat(lines, "\n", range.start_line + 1, range.end_line + 1)
  return {
    status = "success",
    data = {
      for_llm = fmt(
        [[Read file `%s` from lines %s:
````%s
%s
````]],
        request.filepath,
        range_label,
        vim.fn.fnamemodify(request.filepath, ":e"),
        content
      ),
      for_user = fmt("Read file `%s` (%s)", vim.fn.fnamemodify(request.filepath, ":."), range_label),
    },
  }
end

---@class CodeCompanion.Tool.ReadFile: CodeCompanion.Tools.Tool
return {
  name = "read_file",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param opts { input: any, output_cb: fun(msg: table) }
    ---@return nil
    function(self, args, opts)
      local path = file_utils.validate_and_normalize_path(args.filepath)
      local cb = vim.schedule_wrap(opts.output_cb)

      file_utils.read_async(path, function(content, error_message)
        if not content then
          return cb(read_error(path, error_message))
        end

        cb(extract_range(args, split_lines(content)))
      end)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "read_file",
      description = "Read all or part of a file using zero-based, inclusive line ranges."
        .. " Paths may be absolute or relative to the current working directory."
        .. " Call again with another range if more content is needed.",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "Path to an existing file, absolute or relative to the current working directory.",
          },
          start_line = {
            type = "integer",
            description = "Optional zero-based first line. Omit it or use any negative value to start at the beginning;"
              .. " a value past the end is invalid.",
          },
          end_line = {
            type = "integer",
            description = "Optional zero-based last line, inclusive. Omit it or use any negative value to read through the end;"
              .. " values past the end are clamped.",
          },
        },
        required = {
          "filepath",
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
      return self.args.filepath
    end,

    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil|string
    prompt = function(self, meta)
      return fmt("Read `%s`?", vim.fn.fnamemodify(self.args.filepath, ":."))
    end,

    ---@param self CodeCompanion.Tool.ReadFile
    ---@param stdout {for_llm: string, for_user: string}[] The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local output = stdout[1]
      chat:add_tool_output(self, output.for_llm, output.for_user)
    end,

    ---@param self CodeCompanion.Tool.ReadFile
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
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
