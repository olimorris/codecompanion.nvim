local ACP = require("codecompanion.acp")
local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.ACP: CodeCompanion.SlashCommand
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

---Show the value picker for a single config option
---@param config_option table
function SlashCommand:show_values(config_option)
  if config_option.type ~= "select" then
    return utils.notify("Unsupported config option type: " .. (config_option.type or "unknown"), vim.log.levels.WARN)
  end

  local values = ACP.flatten_config_options(config_option.options or {})
  if #values == 0 then
    return utils.notify("No values available for " .. config_option.name, vim.log.levels.WARN)
  end

  local choices = {}
  local value_map = {}
  for i, val in ipairs(values) do
    local prefix = val.value == config_option.currentValue and "* " or "  "
    local display = prefix .. val.name
    if val.group then
      display = display .. " (" .. val.group .. ")"
    end
    if val.description then
      display = display .. " - " .. val.description
    end
    table.insert(choices, display)
    value_map[i] = val
  end

  vim.ui.select(choices, {
    kind = "codecompanion.nvim",
    prompt = config_option.name,
  }, function(_, idx)
    if not idx then
      return
    end

    local selected = value_map[idx]
    if selected.value == config_option.currentValue then
      return utils.notify(selected.name .. " is already selected", vim.log.levels.INFO)
    end

    local ok = self.Chat.acp_connection:set_config_option(config_option.id, selected.value)
    if ok then
      utils.notify("ACP: Changed `" .. config_option.name .. "` to `" .. selected.name .. "`", vim.log.levels.INFO)
      if self.Chat.update_metadata then
        self.Chat:update_metadata()
      end
    else
      utils.notify("Failed to change " .. config_option.name, vim.log.levels.ERROR)
    end
  end)
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
  local Chat = self.Chat

  if not Chat.acp_connection then
    return utils.notify("No ACP connection available", vim.log.levels.WARN)
  end

  local options = Chat.acp_connection:get_config_options({ exclude_categories = { "model" } })
  if #options == 0 then
    return utils.notify("No configuration options available", vim.log.levels.WARN)
  end

  -- Skip straight to values if there's only one option
  if #options == 1 then
    return self:show_values(options[1])
  end

  local choices = {}
  local option_map = {}
  for i, opt in ipairs(options) do
    local display = opt.name
    if opt.description then
      display = display .. " - " .. opt.description
    end
    table.insert(choices, display)
    option_map[i] = opt
  end

  vim.ui.select(choices, {
    kind = "codecompanion.nvim",
    prompt = "Select Configuration Option",
  }, function(_, idx)
    if not idx then
      return
    end
    self:show_values(option_map[idx])
  end)
end

return SlashCommand
