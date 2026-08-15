local tool_helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local fmt = string.format

local START_LINE_ALIAS = "start_line_number_base_zero"
local END_LINE_ALIAS = "end_line_number_base_zero"

---Return a canonical range value, falling back to its hidden legacy alias
---@param args {request: table, name: string, alias: string}
---@return any
local function requested_bound(args)
  local value = rawget(args.request, args.name)
  if value ~= nil then
    return value
  end
  return rawget(args.request, args.alias)
end

---Normalize an optional line bound
---@param args {request: table, name: string, alias: string, default: integer}
---@return integer? line
---@return string? error_message
local function normalize_bound(args)
  local value = requested_bound(args)
  if value == nil or value == vim.NIL or value == "" then
    return args.default
  end

  local line = tonumber(value)
  if not line or line % 1 ~= 0 then
    return nil, fmt("%s must be a valid integer, got: %s", args.name, tostring(value))
  end

  return line < 0 and args.default or line
end

---Resolve and validate the effective line range
---@param args {request: table, line_count: integer}
---@return {start_line: integer, end_line: integer}? range
---@return string? error_message
local function resolve_range(args)
  local request = args.request
  local last_line = math.max(0, args.line_count - 1)
  local start_line, error_message = normalize_bound({
    request = request,
    name = "start_line",
    alias = START_LINE_ALIAS,
    default = 0,
  })
  if error_message then
    return nil, fmt("Error reading `%s`\n%s", request.filepath, error_message)
  end

  local end_line
  end_line, error_message = normalize_bound({
    request = request,
    name = "end_line",
    alias = END_LINE_ALIAS,
    default = last_line,
  })
  if error_message then
    return nil, fmt("Error reading `%s`\n%s", request.filepath, error_message)
  elseif start_line >= args.line_count then
    return nil,
      fmt(
        "Error reading `%s`\nstart_line (%d) is beyond the file's last line (%d)",
        request.filepath,
        start_line,
        last_line
      )
  end

  end_line = math.min(end_line, last_line)
  if start_line > end_line then
    return nil,
      fmt("Error reading `%s`\nstart_line (%d) comes after end_line (%d)", request.filepath, start_line, end_line)
  end

  return { start_line = start_line, end_line = end_line }
end

---Format an effective line range
---@param request {start_line: integer, end_line: integer}
---@return string
local function format_range(request)
  return fmt("%d - %d", request.start_line, request.end_line)
end

---Join the lines in an effective range
---@param args {lines: string[], range: {start_line: integer, end_line: integer}}
---@return string
local function select_lines(args)
  local selected_lines = {}
  for line = args.range.start_line + 1, args.range.end_line + 1 do
    table.insert(selected_lines, args.lines[line])
  end
  return table.concat(selected_lines, "\n")
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
---@param args {request: table, lines: string[]}
---@return {status: "success"|"error", data: string}
local function extract_range(args)
  local request = args.request
  local range, error_message = resolve_range({ request = request, line_count = #args.lines })
  if error_message then
    return {
      status = "error",
      data = error_message,
    }
  end

  request.start_line = range.start_line
  request.end_line = range.end_line

  local output = fmt(
    [[Read file `%s` from lines %s:
````%s
%s
````]],
    request.filepath,
    format_range(request),
    vim.fn.fnamemodify(request.filepath, ":e"),
    select_lines({ lines = args.lines, range = range })
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
    ---@param opts { input: any, output_cb: fun(msg: table) }
    ---@return nil
    function(self, args, opts)
      local path = file_utils.validate_and_normalize_path(args.filepath)
      local cb = vim.schedule_wrap(opts.output_cb)

      file_utils.read_async(path, function(content, error_message)
        if not content then
          return cb({
            status = "error",
            data = fmt("Error reading `%s`\n%s", path, error_message),
          })
        end
        cb(extract_range({ request = args, lines = split_lines(content) }))
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
    ---@param stdout table The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local llm_output = vim.iter(stdout):flatten():join("\n")
      local display_path = vim.fn.fnamemodify(self.args.filepath, ":.")
      chat:add_tool_output(self, llm_output, fmt("Read file `%s` (%s)", display_path, format_range(self.args)))
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
