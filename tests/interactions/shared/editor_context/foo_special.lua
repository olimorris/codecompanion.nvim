local FooSpecial = {}

---@param args CodeCompanion.EditorContext
function FooSpecial.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = FooSpecial })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return nil
function FooSpecial:apply()
  self.Chat:add_message({
    role = "user",
    content = "foo_special",
  }, { _meta = { tag = "editor_context" }, visible = false })
end

return FooSpecial
