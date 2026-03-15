local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.EditorContext.Messages: CodeCompanion.EditorContext
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

---Add Neovim's message history to the chat
---@return nil
function EditorContext:chat_render()
  local messages = vim.fn.execute("messages")
  if not messages or vim.trim(messages) == "" then
    return log:warn("No messages found")
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = "Neovim message history (`:messages`):\n\n````\n" .. vim.trim(messages) .. "\n````",
  }, { _meta = { source = "editor_context", tag = "messages" }, visible = false })
end

---Return inline label and context block for the CLI interaction
---@return { inline: string, block: string }|nil
function EditorContext:cli_render()
  local msgs = vim.fn.execute("messages")
  if not msgs or vim.trim(msgs) == "" then
    log:warn("No messages found")
    return nil
  end

  return {
    inline = "the Neovim messages",
    block = string.format(
      [[- Neovim message history:
````
%s
````]],
      vim.trim(msgs)
    ),
  }
end

return EditorContext
