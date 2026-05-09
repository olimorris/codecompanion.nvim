local tags = require("codecompanion.interactions.shared.tags")

local Bar = {}

---@param args CodeCompanion.EditorContext
function Bar.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = Bar })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return nil
function Bar:chat_render()
  if self.params then
    self.Chat:add_message({
      role = "user",
      content = "bar " .. self.params,
    }, { tag = tags.EDITOR_CONTEXT, visible = false })
    return
  end

  self.Chat:add_message({
    role = "user",
    content = "bar",
  }, { _meta = { tag = tags.EDITOR_CONTEXT }, visible = false })
end

---@return { inline: string, block: string }
function Bar:cli_render()
  if self.params then
    return {
      inline = "inline:bar",
      block = "cli:bar " .. self.params,
    }
  end
  return {
    inline = "inline:bar",
    block = "cli:bar",
  }
end

return Bar
