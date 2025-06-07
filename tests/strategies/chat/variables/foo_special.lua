local FooSpecial = {}

---@param args CodeCompanion.Variable
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
function FooSpecial:output()
  self.Chat:add_message({
    role = "user",
    content = "foo_special",
  }, { tag = "variable", visible = false })
end

return FooSpecial
