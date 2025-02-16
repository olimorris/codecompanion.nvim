local Variable = {}

---@param args CodeCompanion.Variable
function Variable.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = Variable })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return nil
function Variable:output()
  self.Chat:add_message({
    role = "user",
    content = "foo",
  }, { tag = "variable", visible = false })
end

return Variable
