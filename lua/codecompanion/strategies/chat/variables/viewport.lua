local buf_utils = require("codecompanion.utils.buffers")

---@class CodeCompanion.Variable.ViewPort: CodeCompanion.Variable
local Variable = {}

---@param args CodeCompanion.VariableArgs
function Variable.new(args)
  local self = setmetatable({
    chat = args.chat,
    params = args.params,
  }, { __index = Variable })

  return self
end

---Return all of the visible lines in the editor's viewport
---@return string
function Variable:execute()
  local buf_lines = buf_utils.get_visible_lines()

  -- Replace the line numbers with content
  local formatted = {}
  for bufnr, range in pairs(buf_lines) do
    range = range[1]
    table.insert(formatted, buf_utils.format_with_line_numbers(bufnr, range))
  end

  return table.concat(formatted, "\n\n")
end

return Variable
