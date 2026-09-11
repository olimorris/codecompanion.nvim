local picker = require("codecompanion.skills.picker")
local skills = require("codecompanion.skills")

local CONSTANTS = {
  NAME = "Skills",
  PROMPT = "Select a skill",
}

local providers = picker.build({
  prompt = CONSTANTS.PROMPT,
  empty_message = "No skills found",
  preview = true,
  items = function()
    return vim.tbl_map(function(skill)
      return {
        name = skill.name,
        description = skill.description,
        skills = { skill.name },
        path = skill.path,
      }
    end, skills.list())
  end,
})

---@class CodeCompanion.SlashCommand.Skills: CodeCompanion.SlashCommand
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
