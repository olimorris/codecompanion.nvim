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
function Foo:apply()
  self.Chat:add_message({
    role = "user",
    content = "foo",
  }, { _meta = { tag = "editor_context" }, visible = false })
end

return Foo
