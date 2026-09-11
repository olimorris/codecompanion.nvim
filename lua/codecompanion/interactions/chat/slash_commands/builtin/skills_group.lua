local picker = require("codecompanion.skills.picker")
local skills = require("codecompanion.skills")

local fmt = string.format

local CONSTANTS = {
  NAME = "Skills Group",
  PROMPT = "Select a group of skills",
}

local providers = picker.build({
  prompt = CONSTANTS.PROMPT,
  empty_message = "No skill groups found",
  preview = false,
  items = function()
    return vim.tbl_map(function(group)
      return {
        name = fmt("%s (%d)", group.name, #group.skills),
        description = group.description,
        skills = group.skills,
      }
    end, skills.groups())
  end,
})

---@class CodeCompanion.SlashCommand.SkillsGroup: CodeCompanion.SlashCommand
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
  return SlashCommands:set_provider(self, providers)
end

---@param selected { skills: string[] }
---@return nil
function SlashCommand:output(selected)
  if not selected then
    return
  end
  skills.add_to_chat(self.Chat, skills.resolve(selected.skills))
end

return SlashCommand
