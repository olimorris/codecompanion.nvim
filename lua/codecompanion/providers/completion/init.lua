local SlashCommands = require("codecompanion.strategies.chat.slash_commands")
local ToolFilter = require("codecompanion.strategies.chat.agents.tool_filter")
local config = require("codecompanion.config")
local strategy = require("codecompanion.strategies")

local trigger = {
  agents = "@",
  variables = "#",
  slash_commands = "/",
}

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
    if selected.config.references then
      strategy.add_ref(selected.config, chat)
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
        label = trigger.agents .. label,
        name = label,
        type = "agent",
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
        label = trigger.agents .. label,
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
  local variables = config.strategies.chat.variables
  return vim
    .iter(variables)
    :map(function(label, data)
      return {
        label = trigger.variables .. label,
        detail = data.description,
        type = "variable",
      }
    end)
    :totable()
end

return M
