local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

---@class CodeCompanion.Actions
local Actions = {}

local _cached_actions = {}

---Validate the items against the context to determine their visibility
---@param items table The items to validate
---@param context CodeCompanion.BufferContext The buffer context
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
      if utils.contains(item.opts.modes, mode) then
        table.insert(validated_items, item)
      end
    else
      table.insert(validated_items, item)
    end
  end

  return validated_items
end

---Set the items to display in the action palette
---@param context? CodeCompanion.BufferContext
---@return table
function Actions.set_items(context)
  local prompt_library = require("codecompanion.actions.prompt_library")
  local static_actions = require("codecompanion.actions.static")

  if not next(_cached_actions) then
    -- Add static actions
    if config.display.action_palette.opts.show_default_actions then
      for _, action in ipairs(static_actions) do
        action.type = "static"
        table.insert(_cached_actions, action)
      end
    end

    -- Add builtin markdown prompts
    local markdown = require("codecompanion.actions.markdown")
    if config.display.action_palette.opts.show_default_prompt_library then
      local current_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
      local builtin_prompts = markdown.load_from_dir(vim.fs.joinpath(current_dir, "builtins"), context)
      for _, prompt in ipairs(builtin_prompts) do
        prompt.type = "prompt"
        table.insert(_cached_actions, prompt)
      end
    end

    -- Add lua prompts from the prompt library
    if config.prompt_library and not vim.tbl_isempty(config.prompt_library) then
      local prompts = prompt_library.resolve(context, config)
      for _, prompt in ipairs(prompts) do
        -- Exclusions....
        if prompt.name ~= "markdown" then
          prompt.type = "prompt"
          table.insert(_cached_actions, prompt)
        end
      end
    end

    -- Add user markdown prompts
    if config.prompt_library.markdown and config.prompt_library.markdown.dirs then
      for _, dir in ipairs(config.prompt_library.markdown.dirs) do
        if type(dir) == "function" then
          dir = dir(context)
        end
        local user_prompts = markdown.load_from_dir(dir, context)
        for _, prompt in ipairs(user_prompts) do
          prompt.type = "prompt"
          table.insert(_cached_actions, prompt)
        end
      end
    end
  end

  return Actions.validate(_cached_actions, context)
end

---Get the cached action items
---@param context? CodeCompanion.BufferContext
---@return table
function Actions.get_cached_items(context)
  if vim.tbl_isempty(_cached_actions) then
    Actions.set_items(context)
  end

  return _cached_actions
end

---Resolves an item from its short name
---@param name string The short name of the action
---@param context? CodeCompanion.BufferContext
---@return table|nil
function Actions.resolve_from_short_name(name, context)
  if vim.tbl_isempty(_cached_actions) then
    Actions.set_items(context)
  end

  for _, item in ipairs(_cached_actions) do
    if item.opts.short_name == name then
      return item
    end
  end
end

---Resolve the selected item into a strategy
---@param item table
---@param context CodeCompanion.BufferContext
---@return CodeCompanion.Strategies
function Actions.resolve(item, context)
  item = vim.deepcopy(item)
  item = require("codecompanion.actions.markdown").resolve_placeholders(item, context)

  return require("codecompanion.strategies")
    .new({
      buffer_context = context,
      selected = item,
    })
    :start(item.strategy)
end

---Launch the action palette
---@param context CodeCompanion.BufferContext
---@param args? { provider: {name: string, opts: table } } The provider to use
---@return nil
function Actions.launch(context, args)
  local items = Actions.set_items(context)

  if items and #items == 0 then
    return log:warn("No prompts available. Please create some in your config or turn on the prompt library")
  end

  -- Resolve for a specific provider
  local provider = config.display.action_palette.provider
  local provider_opts = {}
  if args and args.provider and args.provider.name then
    provider = args.provider.name
    provider_opts = args.provider.opts or {}
  end

  return require("codecompanion.providers.actions." .. provider)
    .new({ context = context, validate = Actions.validate, resolve = Actions.resolve })
    :picker(items, provider_opts)
end

---Clear the cached actions so they are reloaded next time
---@return nil
function Actions.refresh_cache()
  _cached_actions = {}
end

return Actions
