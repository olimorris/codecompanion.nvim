local Compaction = require("codecompanion.interactions.chat.context_management.compaction")

---@class CodeCompanion.SlashCommand.Compact: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  return setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  return vim.ui.select({ "Yes", "No" }, {
    kind = "codecompanion.nvim",
    prompt = "Generate a compact summary of the conversation so far?",
  }, function(selected)
    if not selected or selected == "No" then
      return
    end
    Compaction.compact(self.Chat, { min_token_savings = 0 })
  end)
end

return SlashCommand
