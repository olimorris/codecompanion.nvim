local Screenshot = {}

---@param args CodeCompanion.EditorContext
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
function Screenshot:apply()
  self.Chat:add_message({
    role = "user",
    content = "Resolved screenshot editor context",
  }, { _meta = { tag = "editor_context" }, visible = false })
end

return Screenshot
