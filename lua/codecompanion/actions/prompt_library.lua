local M = {}

local _prompts = {}

---Resolve the prompts in the prompt library with a view to displaying them in the action palette.
---@param context table
---@param config table
---@return table
function M.resolve(context, config)
  local sort_index = true

  for name, prompt in pairs(config.prompt_library) do
    if config.display.action_palette.opts.show_prompt_library_builtins == false then
      goto continue
    end

    if not prompt.opts or not prompt.opts.index then
      sort_index = false
    end

    if type(prompt.name) == "function" then
      name = prompt.name(context)
    end

    local description = prompt.description
    if type(prompt.description) == "function" then
      description = prompt.description(context)
    end
    if prompt.opts and prompt.opts.slash_cmd then
      description = description
    end

    table.insert(_prompts, {
      condition = prompt.condition,
      context = prompt.context,
      description = description,
      interaction = prompt.interaction or prompt.strategy,
      mcp_servers = prompt.mcp_servers,
      name = name,
      opts = prompt.opts,
      picker = prompt.picker,
      prompts = prompt.prompts,
      rules = prompt.rules,
      tools = prompt.tools,
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

return M
