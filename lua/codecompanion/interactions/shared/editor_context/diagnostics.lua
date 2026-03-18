local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.EditorContext.Diagnostics: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    buffer_context = args.buffer_context or (args.Chat and args.Chat.buffer_context),
    config = args.config,
    params = args.params,
    target = args.target,
  }, { __index = EditorContext })

  return self
end

---Resolve the buffer number, respecting the target if provided
---@return number
function EditorContext:_resolve_bufnr()
  if self.target then
    local buffer_ctx = require("codecompanion.interactions.shared.editor_context.buffer")
    local found = buffer_ctx._find_buffer(self.target)
    if found then
      log:debug("Diagnostics: found buffer %d for target: %s", found, self.target)
      return found
    end
    log:warn("Diagnostics: could not find buffer for target: %s, using current buffer", self.target)
  end

  local ctx = self.buffer_context or (self.Chat and self.Chat.buffer_context)
  return ctx and ctx.bufnr
end

---Return all of the diagnostic information and code for the current buffer
---@return nil
function EditorContext:chat_render()
  local severity = {
    [1] = "ERROR",
    [2] = "WARNING",
    [3] = "INFORMATION",
    [4] = "HINT",
  }

  local bufnr = self:_resolve_bufnr()
  local buf_info = buf_utils.get_info(bufnr)

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
        [[Severity: %s
LSP Message: %s
Code:
````%s
%s
````
]],
        severity[diagnostic.severity],
        diagnostic.message,
        buf_info.filetype,
        table.concat(diagnostic.lines, "\n")
      )
    )
  end

  local content = string.format("Diagnostics for `%s`:\n\n%s", buf_info.path, table.concat(formatted, "\n\n"))

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { _meta = { source = "editor_context", tag = "diagnostics" }, visible = false })
end

---Return inline label and context block for the CLI interaction
---@return { inline: string, block: string }|nil
function EditorContext:cli_render()
  local severity = {
    [1] = "ERROR",
    [2] = "WARNING",
    [3] = "INFORMATION",
    [4] = "HINT",
  }

  local bufnr = self:_resolve_bufnr()
  if not bufnr then
    return nil
  end

  local buf_info = buf_utils.get_info(bufnr)
  local diagnostics = vim.diagnostic.get(bufnr, {
    severity = { min = vim.diagnostic.severity.HINT },
  })

  if #diagnostics == 0 then
    log:warn("No diagnostics found")
    return nil
  end

  local formatted = {}
  for _, diagnostic in ipairs(diagnostics) do
    table.insert(
      formatted,
      string.format("Line %d [%s]: %s", diagnostic.lnum + 1, severity[diagnostic.severity], diagnostic.message)
    )
  end

  return {
    inline = string.format("the diagnostics in @%s", buf_info.relative_path),
    block = string.format(
      [[Diagnostics for @%s:
%s
]],
      buf_info.relative_path,
      table.concat(formatted, "\n")
    ),
  }
end

return EditorContext
