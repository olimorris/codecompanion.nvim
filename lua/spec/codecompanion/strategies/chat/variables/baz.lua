local Variable = {}

---@param args CodeCompanion.Variable
function Variable.new(args)
  local self = setmetatable({
    chat = args.chat,
    params = args.params,
  }, { __index = Variable })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return string
function Variable:execute()
  if self.params then
    return "baz " .. self.params
  end

  return "baz"
end

return Variable
