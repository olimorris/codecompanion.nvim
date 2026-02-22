local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format

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

---Get the diagnostics for a given file
---@param action { filepath: string, severity: string|nil }
---@return { status: "success"|"error", data: string }
local function get_diagnostics(action)
  local filepath = vim.fs.normalize(action.filepath)

  if not filepath or filepath == "" then
    return {
      status = "error",
      data = "filepath parameter is required and cannot be empty",
    }
  end

  local normalized = vim.fn.fnamemodify(filepath, ":p")
  local bufnr = vim.fn.bufnr(normalized)

  local is_existing_buffer = true
  if bufnr == -1 then
    -- Buffer doesn't exist so we need to load it
    bufnr = vim.fn.bufadd(normalized)
    vim.fn.bufload(bufnr)

    -- Trigger filetype detection which fires the FileType autocommand.
    -- LSP auto-attach listens on FileType, so without this the LSP
    -- never attaches to buffers opened via bufadd/bufload.
    local ft = vim.filetype.match({ buf = bufnr })
    if ft then
      vim.bo[bufnr].filetype = ft
    end

    is_existing_buffer = false
  end

  if not api.nvim_buf_is_valid(bufnr) then
    return {
      status = "error",
      data = fmt("Could not resolve a valid buffer for `%s`", filepath),
    }
  end

  local min_severity = vim.diagnostic.severity.HINT
  if action.severity then
    local key = severity_map[string.upper(action.severity)]
    if key then
      local mapped = vim.diagnostic.severity[key]
      if mapped then
        min_severity = mapped
      end
    end
  end

  if not is_existing_buffer then
    -- Wait for LSP to attach to the freshly loaded buffer
    vim.wait(5000, function()
      return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
    end, 50)
  end

  -- Wait for diagnostics to be published (LSP may still be processing after edits)
  if #vim.lsp.get_clients({ bufnr = bufnr }) > 0 then
    vim.wait(5000, function()
      return #vim.diagnostic.get(bufnr) > 0
    end, 50)
  end

  local diagnostics = vim.diagnostic.get(bufnr, {
    severity = { min = min_severity },
  })

  if #diagnostics == 0 then
    return {
      status = "success",
      data = fmt("No diagnostics found for `%s`", filepath),
    }
  end

  local filetype = vim.bo[bufnr].filetype or ""

  local formatted = {}
  for _, diagnostic in ipairs(diagnostics) do
    local lines = {}
    for i = diagnostic.lnum, diagnostic.end_lnum do
      local line_content = vim.trim(table.concat(api.nvim_buf_get_lines(bufnr, i, i + 1, false), ""))
      table.insert(lines, fmt("%d: %s", i + 1, line_content))
    end

    table.insert(
      formatted,
      fmt(
        [[Severity: %s
LSP Message: %s
Code:
````%s
%s
````]],
        severity_labels[diagnostic.severity] or tostring(diagnostic.severity),
        diagnostic.message,
        filetype,
        table.concat(lines, "\n")
      )
    )
  end

  return {
    status = "success",
    data = fmt("Diagnostics for `%s` (%d found):\n\n%s", filepath, #diagnostics, table.concat(formatted, "\n\n")),
  }
end

---@class CodeCompanion.Tool.GetDiagnostics: CodeCompanion.Tools.Tool
return {
  name = "get_diagnostics",
  cmds = {
    ---Execute the diagnostics commands
    ---@param self CodeCompanion.Tool.GetDiagnostics
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      return get_diagnostics(args)
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
