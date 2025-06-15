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
  local content = buf_utils.format_viewport_for_llm(buf_lines)

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { tag = "variable", visible = false })
end

return Variable
