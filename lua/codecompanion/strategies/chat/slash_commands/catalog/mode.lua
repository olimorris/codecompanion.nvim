local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.Mode: CodeCompanion.SlashCommand
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

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local Chat = self.Chat

  if not Chat.acp_connection then
    return utils.notify("No ACP connection available", vim.log.levels.WARN)
  end

  local modes = Chat.acp_connection:get_modes()
  if not modes or not modes.availableModes then
    return utils.notify("Agent does not support session modes", vim.log.levels.WARN)
  end

  -- Build choices for vim.ui.select
  local choices = {}
  local mode_map = {}
  for i, mode in ipairs(modes.availableModes) do
    local display_name = "  " .. mode.name
    if mode.id == modes.currentModeId then
      display_name = "* " .. mode.name
    end
    if mode.description then
      display_name = display_name .. " - " .. mode.description
    end
    table.insert(choices, display_name)
    mode_map[i] = mode.id
  end

  vim.ui.select(choices, {
    prompt = "Select Session Mode",
    kind = "codecompanion.nvim",
  }, function(_, idx)
    if not idx then
      return
    end

    local selected_mode_id = mode_map[idx]
    if selected_mode_id == modes.currentModeId then
      return utils.notify("Already in " .. modes.availableModes[idx].name .. " mode", vim.log.levels.INFO)
    end

    local ok = Chat.acp_connection:set_mode(selected_mode_id)
    if ok then
      -- Find the mode name for the notification
      local mode_name = selected_mode_id
      for _, mode in ipairs(modes.availableModes) do
        if mode.id == selected_mode_id then
          mode_name = mode.name
          break
        end
      end
      utils.notify("Switched to " .. mode_name .. " mode", vim.log.levels.INFO)

      -- Update the chat metadata display
      if Chat.update_metadata then
        Chat:update_metadata()
      end
    else
      utils.notify("Failed to switch mode", vim.log.levels.ERROR)
    end
  end)
end

return SlashCommand
