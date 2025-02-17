local Foo = {}

---@param args CodeCompanion.Variable
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
function Foo:output()
  self.Chat:add_message({
    role = "user",
    content = "foo",
  }, { tag = "variable", visible = false })
end

return Foo
