local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")

---@class CodeCompanion.Variable.ViewPort: CodeCompanion.Variable
local Variable = {}

---@param args CodeCompanion.VariableArgs
function Variable.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = Variable })

  return self
end

---Return all of the visible lines in the editor's viewport
---@return nil
function Variable:output()
  local buf_lines = buf_utils.get_visible_lines()

  -- Replace the line numbers with content
  local formatted = {}
  for bufnr, range in pairs(buf_lines) do
    range = range[1]
    table.insert(formatted, buf_utils.format_with_line_numbers(bufnr, range))
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = table.concat(formatted, "\n\n"),
  }, { tag = "variable", visible = false })
end

return Variable
