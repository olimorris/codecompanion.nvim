---@class CodeCompanion.SlashCommandNow
local SlashCommandNow = {}

---@class CodeCompanion.SlashCommandNow
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu
function SlashCommandNow.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommandNow })

  return self
end

---Execute the slash command
---@return nil
function SlashCommandNow:execute()
  local Chat = self.Chat
  Chat:append_to_buf({ content = os.date("%a, %d %b %Y %H:%M:%S %z") })
end

return SlashCommandNow
