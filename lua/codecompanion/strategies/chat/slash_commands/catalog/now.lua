---@class CodeCompanion.SlashCommand.Now: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommand
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local Chat = self.Chat
  Chat:add_buf_message({ content = os.date("%a, %d %b %Y %H:%M:%S %z") })
end

return SlashCommand
