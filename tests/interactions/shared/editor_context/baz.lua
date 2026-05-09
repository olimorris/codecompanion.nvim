local tags = require("codecompanion.interactions.shared.tags")

local Baz = {}

---@param args CodeCompanion.EditorContext
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
function Baz:apply()
  if self.params then
    self.Chat:add_message({
      role = "user",
      content = "baz " .. self.params,
    }, { _meta = { tag = tags.EDITOR_CONTEXT }, visible = false })
    return
  end

  self.Chat:add_message({
    role = "user",
    content = "baz",
  }, { _meta = { tag = tags.EDITOR_CONTEXT }, visible = false })
end

return Baz
