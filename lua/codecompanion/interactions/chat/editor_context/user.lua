local config = require("codecompanion.config")

---@class CodeCompanion.EditorContext.User: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
    target = args.target,
  }, { __index = EditorContext })

  return self
end

---Return the user's custom context
---@return nil
function EditorContext:apply()
  local id = "<editor_context>" .. self.config.name .. "</editor_context>"

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = self.config.callback(self),
  }, { _meta = { source = "editor_context", tag = self.config.name }, context = { id = id }, visible = false })

  self.Chat.context:add({
    bufnr = self.Chat.bufnr,
    id = id,
    source = "codecompanion.interactions.chat.editor_context.user",
  })
end

return EditorContext
