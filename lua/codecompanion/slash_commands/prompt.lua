local config = require("codecompanion").config
local BaseSlashCommand = require("codecompanion.slash_commands").BaseSlashCommand

local PromptCommand = BaseSlashCommand:extend()

function PromptCommand:init(opts)
  opts = opts or {}
  BaseSlashCommand.init(self, opts)

  self.name = "prompt"
  self.description = "Insert a predefined prompt"
  self.prompts = config.slash_commands.prompts
end

--- Complete file paths for the command.
--- @param params cmp.SourceCompletionApiParams
--- @param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil)
---@diagnostic disable-next-line: unused-local
function PromptCommand:complete(params, callback)
  ---@type CodeCompanion.SlashCommandCompletionItem
  local items = {}
  ---@type CodeCompanion.Chat
  local chat = self.get_chat()

  for name, prompt in pairs(self.prompts) do
    local content = prompt
    if type(content) == "function" then
      content = prompt(chat.context)
    end

    table.insert(items, {
      label = name,
      kind = require("cmp").lsp.CompletionItemKind.Text,
      slash_command_name = self.name,
      documentation = {
        kind = require("cmp").lsp.MarkupKind.Markdown,
        value = content,
      },
    })
  end

  return callback({ items = items, isIncomplete = false })
end

return PromptCommand
