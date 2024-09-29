local config = require("codecompanion").config
local Strategy = require("codecompanion.strategies")
local default = require("codecompanion.actions.providers.default")
local prompt_library = require("codecompanion.actions.prompt_library")
local static_actions = require("codecompanion.actions.static")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

---@class CodeCompanion.Actions
local Actions = {}

local _cached_actions = {}

---Validate the items against the context to determine their visibility
---@param items table The items to validate
---@param context table The buffer context
---@return table
function Actions.validate(items, context)
  local validated_items = {}
  local mode = context.mode:lower()

  for _, item in ipairs(items) do
    if item.condition and type(item.condition) == "function" then
      if item.condition(context) then
        table.insert(validated_items, item)
      end
    elseif item.opts and item.opts.modes then
      if util.contains(item.opts.modes, mode) then
        table.insert(validated_items, item)
      end
    else
      table.insert(validated_items, item)
    end
  end

  return validated_items
end

---Resolve the actions to display in the menu
---@param context table The buffer context
---@return table
function Actions.items(context)
  if not next(_cached_actions) then
    if config.display.action_palette.opts.show_default_actions then
      for _, action in ipairs(static_actions) do
        table.insert(_cached_actions, action)
      end
    end

    if config.prompt_library and util.count(config.prompt_library) > 0 then
      local prompts = prompt_library.resolve(context, config)
      for _, prompt in ipairs(prompts) do
        table.insert(_cached_actions, prompt)
      end
    end
  end

  return Actions.validate(_cached_actions, context)
end

---Resolve the selected item into a strategy
---@param item table
---@param context table
---@return nil
function Actions.resolve(item, context)
  return Strategy.new({
    context = context,
    selected = item,
  }):start(item.strategy)
end

---Launch the action palette
---@param context table The buffer context
---@param provider? string Override the provider in the config
---@return nil
function Actions.launch(context, provider)
  local items = Actions.items(context)

  if items and #items == 0 then
    return log:warn("No prompts available. Please create some in your config or turn on the prompt library")
  end

  local provider_args = { context = context, validate = Actions.validate, resolve = Actions.resolve }

  -- Resolve for a specific provider
  provider = provider or config.display.action_palette.provider
  return require("codecompanion.actions.providers." .. provider).new(provider_args):picker(items)
end

return Actions
