local Screenshot = {}

---@param args CodeCompanion.Variable
function Screenshot.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = Screenshot })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return nil
function Screenshot:output()
  self.Chat:add_message({
    role = "user",
    content = "Resolved screenshot variable",
  }, { tag = "variable", visible = false })
end

return Screenshot
