local Strategy = require("codecompanion.strategies")
local context_utils = require("codecompanion.utils.context")
local api = vim.api

local M = {}

local _prompts = {}

---Resolve the prompts in the prompt library with a view to displaying them in
---the action palette.
---@param config table
---@param context table
---@return table
function M.resolve(context, config)
  local sort_index = true

  for name, prompt in pairs(config.prompt_library) do
    if
      not config.display.action_palette.opts.show_default_prompt_library and (prompt.opts and prompt.opts.is_default)
    then
      goto continue
    end

    if not prompt.opts or not prompt.opts.index then
      sort_index = false
    end

    --TODO: Can we refactor this to name?!
    if type(prompt.name_f) == "function" then
      name = prompt.name_f(context)
    end

    local description = prompt.description
    if type(prompt.description) == "function" then
      description = prompt.description(context)
    end
    if prompt.opts and prompt.opts.slash_cmd then
      description = "(/" .. prompt.opts.slash_cmd .. ") " .. description
    end

    table.insert(_prompts, {
      condition = prompt.condition,
      description = description,
      name = name,
      opts = prompt.opts,
      picker = prompt.picker,
      prompts = prompt.prompts,
      strategy = prompt.strategy,
    })

    ::continue::
  end

  if sort_index then
    table.sort(_prompts, function(a, b)
      return a.opts.index < b.opts.index
    end)
  end

  return _prompts
end

---@param desc table
---@return string|function|nil
local function resolve_description(desc)
  if type(desc) == "string" then
    return desc
  end
  if type(desc) == "function" then
    return desc()
  end
end

---Setup the keymap
---@param map_config table
---@param mode string
---@return nil
local function map(map_config, mode)
  return api.nvim_set_keymap(mode, map_config.opts.mapping, "", {
    callback = function()
      local context = context_utils.get(api.nvim_get_current_buf())

      return Strategy.new({
        context = context,
        selected = map_config,
      }):start(map_config.strategy)
    end,
    desc = resolve_description(map_config.description),
    noremap = true,
    silent = true,
  })
end

---Setup the keymaps for the prompt library
---@param config table
---@return nil
function M.setup_keymaps(config)
  if not config.opts.set_prompt_library_keymaps then
    return
  end

  local prompts = config.prompt_library

  for _, prompt in pairs(prompts) do
    if prompt.opts and prompt.opts.mapping then
      if not config.display.action_palette.opts.show_default_prompt_library and prompt.opts.is_default then
        goto continue
      end
      if prompt.opts.modes and type(prompt.opts.modes) == "table" then
        for _, mode in ipairs(prompt.opts.modes) do
          map(prompt, mode)
        end
      else
        map(prompt, "n")
      end
    end
    ::continue::
  end
end

---Setup the inline slash commands for the prompt library
---@param config table
---@return table
function M.setup_inline_slash_commands(config)
  local slash_cmds = {}
  local prompts = config.prompt_library

  for name, prompt in pairs(prompts) do
    if prompt.opts then
      if not config.display.action_palette.opts.show_default_prompt_library and prompt.opts.is_default then
        goto continue
      end

      if prompt.opts.slash_cmd then
        prompt.name = name
        slash_cmds[prompt.opts.slash_cmd] = prompt
      end

      ::continue::
    end
  end

  return slash_cmds
end

return M
