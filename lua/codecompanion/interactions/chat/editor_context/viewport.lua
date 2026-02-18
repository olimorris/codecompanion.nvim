local buf_utils = require("codecompanion.utils.buffers")
local chat_helpers = require("codecompanion.interactions.chat.helpers")
local config = require("codecompanion.config")

---@class CodeCompanion.EditorContext.ViewPort: CodeCompanion.EditorContext
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

---Return all of the visible lines in the editor's viewport
---@return nil
function EditorContext:apply()
  local buf_lines = buf_utils.get_visible_lines()
  local content = chat_helpers.format_viewport_for_llm(buf_lines)

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { _meta = { source = "editor_context", tag = "viewport" }, visible = false })
end

return EditorContext
