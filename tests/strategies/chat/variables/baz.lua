local Baz = {}

---@param args CodeCompanion.Variable
function Baz.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = Baz })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return nil
function Baz:output()
  if self.params then
    self.Chat:add_message({
      role = "user",
      content = "baz " .. self.params,
    }, { tag = "variable", visible = false })
    return
  end

  self.Chat:add_message({
    role = "user",
    content = "baz",
  }, { tag = "variable", visible = false })
end

return Baz
