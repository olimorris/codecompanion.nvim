local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")

---@class CodeCompanion.EditorContext.LSP: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = EditorContext })

  return self
end

---Return all of the LSP information and code for the current buffer
---@return nil
function EditorContext:output()
  local severity = {
    [1] = "ERROR",
    [2] = "WARNING",
    [3] = "INFORMATION",
    [4] = "HINT",
  }

  local bufnr = self.Chat.buffer_context.bufnr

  local diagnostics = vim.diagnostic.get(bufnr, {
    severity = { min = vim.diagnostic.severity.HINT },
  })

  -- Add code to the diagnostics
  for _, diagnostic in ipairs(diagnostics) do
    for i = diagnostic.lnum, diagnostic.end_lnum do
      if not diagnostic.lines then
        diagnostic.lines = {}
      end
      table.insert(
        diagnostic.lines,
        string.format("%d: %s", i + 1, vim.trim(buf_utils.get_content(bufnr, { i, i + 1 })))
      )
    end
  end

  local formatted = {}
  for _, diagnostic in ipairs(diagnostics) do
    table.insert(
      formatted,
      string.format(
        [[
Severity: %s
LSP Message: %s
Code:
```%s
%s
```
]],
        severity[diagnostic.severity],
        diagnostic.message,
        self.Chat.buffer_context.filetype,
        table.concat(diagnostic.lines, "\n")
      )
    )
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = table.concat(formatted, "\n\n"),
  }, { _meta = { tag = "editor_context" }, visible = false })
end

return EditorContext
