local SlashCommands = require("codecompanion.strategies.chat.slash_commands")
local config = require("codecompanion.config")
local strategy = require("codecompanion.strategies")
local util = require("codecompanion.utils")

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

  for _, v in pairs(config.prompt_library) do
    if v.opts and v.opts.is_slash_cmd and v.strategy == "chat" then
      table.insert(slash_commands, {
        label = "/" .. v.opts.short_name,
        detail = v.description,
        config = v,
        type = "slash_command",
        from_prompt_library = true,
      })
    end
  end

  return slash_commands
end

---Execute selected slash command
---@param selected table The selected item from the completion menu
---@param chat CodeCompanion.Chat
---@return nil
function M.slash_commands_execute(selected, chat)
  if selected.from_prompt_library then
    local prompts = strategy.evaluate_prompts(selected.config.prompts, selected.context)
    vim.iter(prompts):each(function(prompt)
      if prompt.role == config.constants.SYSTEM_ROLE then
        chat:add_message(prompt, { visible = false })
      elseif prompt.role == config.constants.USER_ROLE then
        chat:add_buf_message(prompt)
      end
      -- change adapter for custom prompt
      if
        not vim.g.codecompanion_adapter
        or (
          vim.g.codecompanion_adapter
          and selected.config.opts
          and selected.config.opts.adapter
          and selected.config.opts.adapter.name
          and selected.config.opts.adapter.name ~= vim.g.codecompanion_adapter
        )
      then
        chat.adapter = require("codecompanion.adapters").resolve(config.adapters[selected.config.opts.adapter.name])
        util.fire("ChatAdapter", { bufnr = chat.bufnr, adapter = chat.adapter })
        chat:apply_settings()
      end
    end)
  else
    SlashCommands:execute(selected, chat)
  end
end

---Return the tools to be used for completion
---@return table
function M.tools()
  -- Add agents
  local items = vim
    .iter(config.strategies.agent)
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
    .iter(config.strategies.agent.tools)
    :filter(function(label)
      return label ~= "opts"
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
