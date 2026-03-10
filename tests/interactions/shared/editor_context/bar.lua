local Bar = {}

---@param args CodeCompanion.EditorContext
function Bar.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = Bar })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return nil
function Bar:apply()
  if self.params then
    self.Chat:add_message({
      role = "user",
      content = "bar " .. self.params,
    }, { tag = "editor_context", visible = false })
    return
  end

  self.Chat:add_message({
    role = "user",
    content = "bar",
  }, { _meta = { tag = "editor_context" }, visible = false })
end

---@return string
function Bar:apply_cli()
  if self.params then
    return "cli:bar " .. self.params
  end
  return "cli:bar"
end

return Bar
