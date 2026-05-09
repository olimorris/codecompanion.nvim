local tags = require("codecompanion.interactions.shared.tags")

local Foo = {}

---@param args CodeCompanion.EditorContext
function Foo.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = Foo })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return nil
function Foo:chat_render()
  self.Chat:add_message({
    role = "user",
    content = "foo",
  }, { _meta = { tag = tags.EDITOR_CONTEXT }, visible = false })
end

---@return { inline: string, block: string }
function Foo:cli_render()
  return {
    inline = "inline:foo",
    block = "cli:foo",
  }
end

return Foo
