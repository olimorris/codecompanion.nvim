local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format

local CONSTANTS = {
  MAX_CODE_LINES = 8,
  MAX_WAIT = 5000,
  WAIT_AFTER_EACH_CHANGE = 250,
  WAIT_FOR_FIRST_DIAGNOSTICS = 2000,
}

local severity_labels = {
  [1] = "ERROR",
  [2] = "WARNING",
  [3] = "INFORMATION",
  [4] = "HINT",
}

-- Map schema severity names to vim.diagnostic.severity keys
local severity_map = {
  ERROR = "ERROR",
  WARNING = "WARN",
  INFORMATION = "INFO",
  HINT = "HINT",
}

---Resolve a filepath to a loaded buffer, reading it in the background if it isn't open
---@param filepath string
---@return { bufnr: number|nil, error: string|nil, freshly_loaded: boolean }
local function resolve_buffer(filepath)
  local bufnr = vim.fn.bufadd(filepath)
  if bufnr == 0 or not api.nvim_buf_is_valid(bufnr) then
    return {
      error = fmt("`%s` could not be opened. Check the path points at a file and try again", filepath),
      freshly_loaded = false,
    }
  end

  if api.nvim_buf_is_loaded(bufnr) then
    return { bufnr = bufnr, freshly_loaded = false }
  end

  local ok, err = pcall(vim.fn.bufload, bufnr)
  if not ok then
    return {
      error = fmt("`%s` could not be read. Neovim failed to open it: %s", filepath, err),
      freshly_loaded = false,
    }
  end

  -- LSP auto-attach listens on FileType, so cover a config with detection turned off
  if vim.bo[bufnr].filetype == "" then
    local filetype = vim.filetype.match({ buf = bufnr })
    if filetype then
      vim.bo[bufnr].filetype = filetype
    end
  end

  return { bufnr = bufnr, freshly_loaded = true }
end

---Call back once the buffer's diagnostics have stopped arriving, or the waits elapse
---@param bufnr number
---@param opts { freshly_loaded: boolean }
---@param callback fun()
---@return nil
local function on_diagnostics(bufnr, opts, callback)
  if not opts.freshly_loaded and vim.tbl_isempty(vim.lsp.get_clients({ bufnr = bufnr })) then
    return callback()
  end

  local group = api.nvim_create_augroup("codecompanion.get_diagnostics." .. bufnr, { clear = true })
  local responded = false
  local scheduled = 0

  local function respond()
    if responded then
      return
    end
    responded = true
    pcall(api.nvim_del_augroup_by_id, group)
    callback()
  end

  ---Respond once the delay is up, unless a later change schedules a new one first
  ---@param delay number
  ---@return nil
  local function respond_in(delay)
    scheduled = scheduled + 1
    local generation = scheduled
    vim.defer_fn(function()
      if generation == scheduled then
        respond()
      end
    end, delay)
  end

  api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(request)
      if request.buf == bufnr then
        respond_in(CONSTANTS.WAIT_AFTER_EACH_CHANGE)
      end
    end,
  })
  api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(request)
      if request.buf == bufnr then
        respond_in(CONSTANTS.WAIT_FOR_FIRST_DIAGNOSTICS)
      end
    end,
  })

  respond_in(CONSTANTS.WAIT_FOR_FIRST_DIAGNOSTICS)
  vim.defer_fn(respond, CONSTANTS.MAX_WAIT)
end

---Format diagnostics as a list of messages followed by the source lines they point at
---@param args { bufnr: number, diagnostics: table[], display_path: string }
---@return string
local function format_diagnostics(args)
  local bufnr = args.bufnr

  table.sort(args.diagnostics, function(a, b)
    if a.lnum == b.lnum then
      return (a.col or 0) < (b.col or 0)
    end
    return a.lnum < b.lnum
  end)

  local last_line = api.nvim_buf_line_count(bufnr) - 1
  local messages = {}
  local wanted_lines = {}

  for _, diagnostic in ipairs(args.diagnostics) do
    local origin = diagnostic.source or ""
    if diagnostic.code then
      origin = origin == "" and tostring(diagnostic.code) or fmt("%s[%s]", origin, diagnostic.code)
    end

    table.insert(
      messages,
      fmt(
        "%d:%d %s %s%s",
        diagnostic.lnum + 1,
        (diagnostic.col or 0) + 1,
        severity_labels[diagnostic.severity] or tostring(diagnostic.severity),
        origin ~= "" and (origin .. " ") or "",
        (vim.trim(diagnostic.message):gsub("\n", "\n  "))
      )
    )

    -- Diagnostics can outlive the edit that produced them, so their range may now sit beyond the end of the buffer
    local start_line = math.max(0, diagnostic.lnum)
    local end_line =
      math.min(diagnostic.end_lnum or diagnostic.lnum, last_line, start_line + CONSTANTS.MAX_CODE_LINES - 1)
    for line = start_line, end_line do
      wanted_lines[line] = true
    end
  end

  local numbers = vim.tbl_keys(wanted_lines)
  table.sort(numbers)

  local code = {}
  for _, line in ipairs(numbers) do
    table.insert(code, fmt("%d: %s", line + 1, api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""))
  end

  return fmt(
    [[Diagnostics for `%s` (%d found):
%s

Code:
````%s
%s
````]],
    args.display_path,
    #args.diagnostics,
    table.concat(messages, "\n"),
    vim.bo[bufnr].filetype or "",
    table.concat(code, "\n")
  )
end

---Get the diagnostics for a given file
---@param action { filepath: string, severity: string|nil }
---@param callback fun(msg: { status: "success"|"error", data: string })
---@return nil
local function get_diagnostics(action, callback)
  if not action.filepath or action.filepath == "" then
    return callback({
      status = "error",
      data = "filepath parameter is required and cannot be empty",
    })
  end

  local filepath = file_utils.validate_and_normalize_path(action.filepath)
  if not filepath or not file_utils.exists(filepath) then
    return callback({
      status = "error",
      data = fmt(
        "`%s` does not exist. Check the path is correct and relative to the current working directory",
        action.filepath
      ),
    })
  end

  local display_path = vim.fn.fnamemodify(filepath, ":.")
  local buffer = resolve_buffer(filepath)
  local bufnr = buffer.bufnr
  if not bufnr then
    return callback({ status = "error", data = buffer.error })
  end

  local min_severity = vim.diagnostic.severity.HINT
  if action.severity then
    local key = severity_map[string.upper(action.severity)]
    if key then
      min_severity = vim.diagnostic.severity[key] or min_severity
    end
  end

  on_diagnostics(bufnr, { freshly_loaded = buffer.freshly_loaded }, function()
    if not api.nvim_buf_is_valid(bufnr) then
      return callback({
        status = "error",
        data = fmt("The buffer for `%s` was closed before its diagnostics could be read", display_path),
      })
    end

    local diagnostics = vim.diagnostic.get(bufnr, { severity = { min = min_severity } })
    if #diagnostics == 0 then
      return callback({
        status = "success",
        data = fmt("No diagnostics found for `%s`", display_path),
      })
    end

    callback({
      status = "success",
      data = format_diagnostics({ bufnr = bufnr, diagnostics = diagnostics, display_path = display_path }),
    })
  end)
end

---@class CodeCompanion.Tool.GetDiagnostics: CodeCompanion.Tools.Tool
return {
  name = "get_diagnostics",
  cmds = {
    ---Execute the diagnostics commands
    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param args table The arguments from the LLM's tool call
    ---@param opts { input: any, output_cb: fun(msg: table) }
    ---@return nil
    function(self, args, opts)
      get_diagnostics(args, vim.schedule_wrap(opts.output_cb))
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "get_diagnostics",
      description = "Get the LSP diagnostics for a given file. Returns all diagnostic messages (errors, warnings, hints, and information) along with the relevant code lines. Use this to understand what issues exist in a file before attempting to fix them.",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The absolute path to the file to retrieve diagnostics for, including its filename and extension.",
          },
          severity = {
            type = "string",
            description = "The minimum severity level to include. One of: ERROR, WARNING, INFORMATION, HINT. Defaults to HINT (all diagnostics).",
            enum = { "ERROR", "WARNING", "INFORMATION", "HINT" },
          },
        },
        required = {
          "filepath",
        },
      },
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param opts { tools: CodeCompanion.Tools }
    ---@return nil
    on_exit = function(self, opts)
      log:trace("[Get Diagnostics Tool] on_exit handler executed")
    end,
  },
  output = {
    ---Returns the command that will be executed
    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param opts { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, opts)
      return self.args.filepath
    end,

    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil|string
    prompt = function(self, meta)
      return fmt("Get diagnostics for `%s`?", vim.fn.fnamemodify(self.args.filepath, ":."))
    end,

    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param stdout table The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local llm_output = vim.iter(stdout):flatten():join("\n")
      local display_path = vim.fn.fnamemodify(self.args.filepath, ":.")
      chat:add_tool_output(self, llm_output, fmt("Got diagnostics for `%s`", display_path))
    end,

    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Get Diagnostics Tool] Error output: %s", stderr)
      chat:add_tool_output(self, errors)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param meta { tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      local message = "The user rejected the get diagnostics tool"
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
}
