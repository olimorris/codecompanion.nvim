local helpers = require("codecompanion.strategies.chat.memory.helpers")
local memory = require("codecompanion.strategies.chat.memory")

---@class CodeCompanion.SlashCommand.Memory: CodeCompanion.SlashCommand
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
  vim.ui.select(helpers.list(), {
    prompt = "Select a memory",
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
  return memory
    .init({
      name = selected.name,
      opts = selected.opts,
      parser = selected.parser,
      rules = selected.rules,
    })
    :make(self.Chat)
end

return SlashCommand
