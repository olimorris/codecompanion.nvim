local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")

---@class CodeCompanion.Variable.User: CodeCompanion.Variable
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

---Return the user's custom variable
---@return nil
function Variable:output()
  local id = "<var>" .. self.config.name .. "</var>"

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = self.config.callback(),
  }, { reference = id, tag = "variable", visible = false })

  self.Chat.references:add({
    bufnr = self.Chat.bufnr,
    id = id,
    source = "codecompanion.strategies.chat.variables.user",
  })
end

return Variable
