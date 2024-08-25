local BaseSlashCommand = require("codecompanion.slash_commands").BaseSlashCommand

local TerminalCommand = BaseSlashCommand:extend()

function TerminalCommand:init(opts)
  opts = opts or {}
  BaseSlashCommand.init(self, opts)
  self.name = "terminal"
  self.description = "Insert terminal output"
end

--- Complete file paths for the command.
--- @param params cmp.SourceCompletionApiParams
--- @param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil)
---@diagnostic disable-next-line: unused-local
function TerminalCommand:execute(params, callback)
  --TODO: Implement terminal command
  return callback()
end

---Resolve completion item (optional). This is called right before the completion is about to be displayed.
---Useful for setting the text shown in the documentation window (`completion_item.documentation`).
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
---@diagnostic disable-next-line: unused-local
function TerminalCommand:complete(completion_item, callback)
  --TODO: Implement terminal command
  return callback()
end

return TerminalCommand
