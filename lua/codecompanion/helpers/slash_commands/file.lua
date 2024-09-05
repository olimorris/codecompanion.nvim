local config = require("codecompanion").config

local file = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

CONSTANTS = {
  NAME = "File",
  PROMPT = "Select a file",
}

---Output from the slash command in the chat buffer
---@param SlashCommand CodeCompanion.SlashCommandFile
---@param selected table The selected item from the provider { relative_path = string, path = string }
---@return nil
local function output(SlashCommand, selected)
  if not config.opts.send_code and (SlashCommand.config.opts and SlashCommand.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local ft = file.get_filetype(selected.path)
  local content = file.read(selected.path)

  if content == "" then
    return log:warn("Could not read the file: %s", selected.path)
  end

  local Chat = SlashCommand.Chat
  Chat:append_to_buf({ content = "[!" .. CONSTANTS.NAME .. ": `" .. selected.relative_path .. "`]\n" })
  Chat:append_to_buf({ content = "```" .. ft .. "\n" .. content .. "```" })
  Chat:fold_code()
end

local Providers = {
  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommandFile
  ---@return nil
  telescope = function(SlashCommand)
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then
      return log:error("Telescope is not installed")
    end

    telescope.find_files({
      prompt_title = CONSTANTS.PROMPT,
      attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            selection = { relative_path = selection[1], path = selection.path }
            output(SlashCommand, selection)
          end
        end)

        return true
      end,
    })
  end,
}

---@class CodeCompanion.SlashCommandFile
local SlashCommandFile = {}

---@class CodeCompanion.SlashCommandFile
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu
function SlashCommandFile.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommandFile })

  return self
end

---Execute the slash command
---@return nil
function SlashCommandFile:execute()
  if self.config.opts and self.config.opts.provider then
    local provider = Providers[self.config.opts.provider]
    if not provider then
      return log:error("Provider for the file slash command could not found: %s", self.config.opts.provider)
    end
    provider(self)
  else
    Providers.telescope(self)
  end
end

return SlashCommandFile
