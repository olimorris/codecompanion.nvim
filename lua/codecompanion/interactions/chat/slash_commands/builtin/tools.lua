local picker = require("codecompanion.providers.slash_commands.picker")

local CONSTANTS = {
  NAME = "Tools",
  PROMPT = "Select tools",
}

---@param chat CodeCompanion.Chat
---@return CodeCompanion.SlashCommand.PickerItem[]
local function list_tools(chat)
  local tools_config = chat.tools:refresh({ adapter = chat.adapter }).tools_config
  local registry = chat.tool_registry
  local items = {}

  for name, group in pairs(tools_config.groups or {}) do
    if name ~= "tools" and not registry.groups[name] then
      table.insert(items, { name = name, description = group.description })
    end
  end

  for name, tool in pairs(tools_config) do
    if name ~= "opts" and name ~= "groups" and tool.visible ~= false and not registry.in_use[name] then
      table.insert(items, { name = name, description = tool.description })
    end
  end

  table.sort(items, function(a, b)
    return a.name < b.name
  end)

  return items
end

---@class CodeCompanion.SlashCommand.Tools: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  local providers = picker.build_list_pickers({
    prompt = CONSTANTS.PROMPT,
    empty_message = "No tools to add",
    preview = false,
    items = function()
      return list_tools(self.Chat)
    end,
  })

  return SlashCommands:set_provider(self, providers)
end

---@param selected { name: string }
---@return nil
function SlashCommand:output(selected)
  if not selected then
    return
  end
  self.Chat.tool_registry:add(selected.name, { config = self.Chat.tools.tools_config })
end

return SlashCommand
