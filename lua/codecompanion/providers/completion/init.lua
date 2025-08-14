local SlashCommands = require("codecompanion.strategies.chat.slash_commands")
local ToolFilter = require("codecompanion.strategies.chat.tools.tool_filter")
local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local strategy = require("codecompanion.strategies")

local trigger = {
  tools = "@",
  variables = "#",
  slash_commands = "/",
}

local api = vim.api
local _vars_aug = nil
local _vars_cache = nil
local _vars_cache_valid = false

---Setup the variable cache
---@return nil
local function _vars_cache_setup()
  if _vars_aug then
    return
  end

  _vars_aug = api.nvim_create_augroup("codecompanion.chat.variables", { clear = true })

  -- Invalidate the cache on the following events
  api.nvim_create_autocmd({
    "BufAdd",
    "BufDelete",
    "BufWipeout",
    "BufUnload",
    "BufNewFile",
    "BufReadPost",
  }, {
    group = _vars_aug,
    callback = function()
      _vars_cache_valid = false
    end,
  })
end

local M = {}

---Return the slash commands to be used for completion
---@return table
function M.slash_commands()
  local slash_commands = vim
    .iter(config.strategies.chat.slash_commands)
    :filter(function(name)
      return name ~= "opts"
    end)
    :map(function(label, v)
      return {
        label = trigger.slash_commands .. label,
        detail = v.description,
        config = v,
        type = "slash_command",
      }
    end)
    :totable()

  vim
    .iter(pairs(config.prompt_library))
    :filter(function(_, v)
      return v.opts and v.opts.is_slash_cmd and v.strategy == "chat"
    end)
    :each(function(_, v)
      table.insert(slash_commands, {
        label = "/" .. v.opts.short_name,
        detail = v.description,
        config = v,
        type = "slash_command",
        from_prompt_library = true,
      })
    end)

  return slash_commands
end

---Execute selected slash command
---@param selected table The selected item from the completion menu
---@param chat CodeCompanion.Chat
---@return nil
function M.slash_commands_execute(selected, chat)
  if selected.from_prompt_library then
    --TODO: Remove `selected.config.references` check in v18.0.0
    local context = selected.config.references or selected.config.context
    if context then
      strategy.add_context(selected.config, chat)
    end

    local prompts = strategy.evaluate_prompts(selected.config.prompts, selected.context)
    vim.iter(prompts):each(function(prompt)
      if prompt.role == config.constants.SYSTEM_ROLE then
        chat:add_message(prompt, { visible = false })
      elseif prompt.role == config.constants.USER_ROLE then
        chat:add_buf_message(prompt)
      end
    end)
  else
    SlashCommands:execute(selected, chat)
  end
end

---Return the tools to be used for completion
---@return table
function M.tools()
  -- Get filtered tools configuration (this uses the cache!)
  local tools = ToolFilter.filter_enabled_tools(config.strategies.chat.tools)

  -- Add groups
  local items = vim
    .iter(tools.groups)
    :filter(function(label)
      return label ~= "tools"
    end)
    :map(function(label, v)
      return {
        label = trigger.tools .. label,
        name = label,
        type = "tool",
        callback = v.callback,
        detail = v.description,
      }
    end)
    :totable()

  -- Add tools
  vim
    .iter(tools)
    :filter(function(label, value)
      return label ~= "opts" and label ~= "groups" and value.visible ~= false
    end)
    :each(function(label, v)
      table.insert(items, {
        label = trigger.tools .. label,
        name = label,
        type = "tool",
        callback = v.callback,
        detail = v.description,
      })
    end)

  return items
end

---Return the variables to be used for completion
---@return table
function M.variables()
  _vars_cache_setup()
  if _vars_cache and _vars_cache_valid then
    return _vars_cache
  end

  local config_vars = config.strategies.chat.variables
  local variables = vim
    .iter(config_vars)
    :map(function(label, data)
      return {
        label = trigger.variables .. label,
        detail = data.description,
        type = "variable",
      }
    end)
    :totable()

  local open_buffers = buf_utils.get_open()

  local name_counts = vim.iter(open_buffers):fold({}, function(acc, item)
    acc[item.name] = (acc[item.name] or 0) + 1
    return acc
  end)

  local buffers = vim
    .iter(open_buffers)
    :map(function(buf)
      local name
      if name_counts[buf.name] > 1 then
        name = buf.short_path
      else
        name = buf.name
      end

      return {
        label = trigger.variables .. "buffer:" .. name,
        detail = "Path: " .. buf.relative_path .. "\nBuffer: " .. buf.bufnr,
        type = "variable",
      }
    end)
    :totable()

  _vars_cache = vim.list_extend(variables, buffers)
  _vars_cache_valid = true

  return _vars_cache
end

return M
