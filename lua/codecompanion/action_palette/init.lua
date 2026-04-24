local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local prompt_library = require("codecompanion.prompt_library")
local utils = require("codecompanion.utils")

---@class CodeCompanion.ActionPalette
local ActionPalette = {}

local _cached_items = {}

---Insert prompts into the cached items
---@param prompts table
---@param opts? { is_markdown: boolean }
local function insert_prompts(prompts, opts)
  for _, prompt in ipairs(prompts) do
    if not prompt.opts then
      prompt.opts = {}
    end
    prompt.opts.type = "prompt"
    if opts and opts.is_markdown then
      prompt.opts.is_markdown = true
    end
    if prompt.opts.enabled ~= false then
      table.insert(_cached_items, prompt)
    end
  end
end

---Validate the items against the context to determine their visibility
---@param items table The items to validate
---@param context CodeCompanion.BufferContext The buffer context
---@return table
function ActionPalette.validate(items, context)
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
---@param context CodeCompanion.BufferContext
---@return table
function ActionPalette.set_items(context)
  if not next(_cached_items) then
    local static_items = require("codecompanion.action_palette.static")

    -- Add static actions
    if config.display.action_palette.opts.show_preset_actions then
      for _, action in ipairs(static_items) do
        action.type = "static"
        table.insert(_cached_items, action)
      end
    end

    -- Add builtin markdown prompts
    if config.display.action_palette.opts.show_preset_prompts then
      insert_prompts(prompt_library.load_builtins(context), { is_markdown = true })
    end

    -- Add lua prompts from the prompt library
    if config.prompt_library and not vim.tbl_isempty(config.prompt_library) then
      local prompts = prompt_library.resolve(context, config)
      insert_prompts(vim.tbl_filter(function(p)
        return p.name ~= "markdown"
      end, prompts))
    end

    -- Add user markdown prompts
    if config.prompt_library.markdown and config.prompt_library.markdown.dirs then
      local markdown = require("codecompanion.prompt_library.markdown")
      for _, dir in ipairs(config.prompt_library.markdown.dirs) do
        if type(dir) == "function" then
          dir = dir(context)
        end
        insert_prompts(markdown.load_from_dir(dir, context), { is_markdown = true })
      end
    end
  end

  return ActionPalette.validate(_cached_items, context)
end

---Get the cached items
---@param context CodeCompanion.BufferContext
---@return table
function ActionPalette.get_cached_items(context)
  ActionPalette.set_items(context)
  return _cached_items
end

---Resolve an item from an alias
---@param alias string
---@param context CodeCompanion.BufferContext
---@return table|nil
function ActionPalette.resolve_from_alias(alias, context)
  ActionPalette.set_items(context)

  for _, item in ipairs(_cached_items) do
    if item.opts.alias == alias then
      return item
    end
  end
end

---Resolve the selected item into an interaction
---@param item table
---@param context CodeCompanion.BufferContext
---@return CodeCompanion.Interactions
function ActionPalette.resolve(item, context)
  item = vim.deepcopy(item)
  item = require("codecompanion.prompt_library.markdown").resolve_placeholders(item, context)

  return require("codecompanion.interactions")
    .new({
      buffer_context = context,
      selected = item,
    })
    :start(item.interaction)
end

---Launch the action palette
---@param context CodeCompanion.BufferContext
---@param args? { provider: {name: string, opts: table } } The provider to use
---@return nil
function ActionPalette.launch(context, args)
  local items = ActionPalette.set_items(context)

  if items and #items == 0 then
    return log:warn("No prompts available. Please create some in your config or turn on the prompt library")
  end

  local provider = config.display.action_palette.provider
  local provider_opts = {}
  if args and args.provider and args.provider.name then
    provider = args.provider.name
    provider_opts = args.provider.opts or {}
  end

  return require("codecompanion.providers.action_palette." .. provider)
    .new({ context = context, validate = ActionPalette.validate, resolve = ActionPalette.resolve })
    :picker(items, provider_opts)
end

---Clear the cached items so they are reloaded next time
---@param context CodeCompanion.BufferContext
---@return nil
function ActionPalette.refresh_cache(context)
  _cached_items = {}
  ActionPalette.set_items(context)
end

return ActionPalette
