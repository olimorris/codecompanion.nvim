local helpers = require("codecompanion.interactions.chat.rules.helpers")
local rules = require("codecompanion.interactions.chat.rules")

---@class CodeCompanion.SlashCommand.Rules: CodeCompanion.SlashCommand
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

function SlashCommand:execute()
  vim.ui.select(helpers.list(self.Chat), {
    prompt = "Select a rule",
    format_item = function(item)
      return item.name
    end,
  }, function(selected)
    if not selected then
      return
    end

    return self:output(selected)
  end)
end

---Execute the slash command
---@param selected table
---@return nil
function SlashCommand:output(selected)
  return rules
    .new({
      name = selected.name,
      files = selected.files,
      opts = selected.opts,
      parser = selected.parser,
    })
    :make({ chat = self.Chat, force = true })
end

return SlashCommand
