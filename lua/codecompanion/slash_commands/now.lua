local BaseSlashCommand = require("codecompanion.slash_commands").BaseSlashCommand
local ui = require("codecompanion.utils.ui")

--- NowCommand class for inserting current date and time.
--- @class CodeCompanion.NowCommand: CodeCompanion.BaseSlashCommand
local NowCommand = BaseSlashCommand:extend()

function NowCommand:init(opts)
  opts = opts or {}
  BaseSlashCommand.init(self, opts)
  self.name = "now"
  self.description = "Insert current date and time"
end

--- Execute the diagnostics command with the provided chat context and arguments.
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
---@diagnostic disable-next-line: unused-local
function NowCommand:execute(completion_item, callback)
  local datetime = os.date("%a, %d %b %Y %H:%M:%S %z")
  local formatted_content = string.format("Current date and time: %s", datetime)
  self.chat:append({ content = formatted_content })
  ui.buf_scroll_to_end(self.chat.bufnr)

  return callback()
end

---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil)
---@diagnostic disable-next-line: unused-local
function NowCommand:complete(params, callback)
  return callback()
end

return NowCommand
