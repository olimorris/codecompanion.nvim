local config = require("codecompanion.config")

---@class CodeCompanion.SlashCommand.Basic: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
    opts = args.opts,
  }, { __index = SlashCommand })

  return self
end

function SlashCommand:output(selected, opts)
  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = "Basic Slash Command",
  }, { context_id = id, visible = false })
end

return SlashCommand
