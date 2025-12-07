local filter = require("codecompanion.interactions.chat.helpers.filter")

---@class CodeCompanion.SlashCommands.Filter
local Filter = filter.create_filter({
  skip_keys = { "opts" },
})

-- Maintain backward compatibility with existing API
Filter.filter_enabled_slash_commands = Filter.filter_enabled
Filter.is_slash_command_enabled = Filter.is_enabled

return Filter
