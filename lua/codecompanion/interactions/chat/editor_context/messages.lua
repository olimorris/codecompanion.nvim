local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.EditorContext.Messages: CodeCompanion.EditorContext
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

---Add Neovim's message history to the chat
---@return nil
function EditorContext:apply()
  local messages = vim.fn.execute("messages")
  if not messages or vim.trim(messages) == "" then
    return log:warn("No messages found")
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = "Neovim message history (`:messages`):\n\n````\n" .. vim.trim(messages) .. "\n````",
  }, { _meta = { source = "editor_context", tag = "messages" }, visible = false })
end

return EditorContext
