local filter_base = require("codecompanion.utils.filter_base")

---@class CodeCompanion.SlashCommands.Filter
local Filter = filter_base.create_filter("Slash Command", {
  skip_keys = { "opts" },
})

-- Maintain backward compatibility with existing API
Filter.filter_enabled_slash_commands = Filter.filter_enabled
Filter.is_slash_command_enabled = Filter.is_enabled

return Filter
