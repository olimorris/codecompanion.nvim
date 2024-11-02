local buf_utils = require("codecompanion.utils.buffers")

---@class CodeCompanion.Variable.LSP: CodeCompanion.Variable
---@field new fun(args: CodeCompanion.Variable): CodeCompanion.Variable.LSP
---@field execute fun(self: CodeCompanion.Variable.LSP): string
local Variable = {}

---@param args CodeCompanion.Variable
function Variable.new(args)
  local self = setmetatable({
    chat = args.chat,
    params = args.params,
  }, { __index = Variable })

  return self
end

---Return all of the LSP information and code for the current buffer
---@return string
function Variable:execute()
  local severity = {
    [1] = "ERROR",
    [2] = "WARNING",
    [3] = "INFORMATION",
    [4] = "HINT",
  }

  local bufnr = self.chat.context.bufnr

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
        self.chat.context.filetype,
        table.concat(diagnostic.lines, "\n")
      )
    )
  end

  return table.concat(formatted, "\n\n")
end

return Variable
