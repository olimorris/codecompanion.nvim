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
  Chat:add_to_prompt(os.date("%a, %d %b %Y %H:%M:%S %z") --[[@as string]])
end

return SlashCommand
