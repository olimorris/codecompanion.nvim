local SlashCommands = require("codecompanion.strategies.chat.slash_commands")
local ToolFilter = require("codecompanion.strategies.chat.tools.tool_filter")
local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local strategy = require("codecompanion.strategies")

local api = vim.api

local function get_acp_trigger()
  if config.strategies.chat.slash_commands.opts and config.strategies.chat.slash_commands.opts.acp then
    return config.strategies.chat.slash_commands.opts.acp.trigger or "\\"
  end
  return "\\"
end

local trigger = {
  tools = "@",
  variables = "#",
  slash_commands = "/",
  acp_commands = get_acp_trigger(),
}

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

-- Cache adapter info per buffer (type + evaluated tools)
local adapter_cache = {}

local aug = api.nvim_create_augroup("codecompanion.completion", { clear = true })

api.nvim_create_autocmd("User", {
  group = aug,
  pattern = "CodeCompanionChatModel",
  callback = function(args)
    local bufnr = args.data.bufnr
    if args.data.adapter then
      ToolFilter.refresh_cache()

      local evaluated_tools = {}

      -- Evaluate the available tools from the adapter
      if args.data.adapter.available_tools then
        for tool_name, tool_config in pairs(args.data.adapter.available_tools) do
          local should_show = true
          if tool_config.condition and type(tool_config.condition) == "function" then
            should_show = tool_config.condition(args.data.adapter, args.data.model)
          end

          if should_show then
            evaluated_tools[tool_name] = tool_config
          end
        end
      end

      adapter_cache[bufnr] = {
        type = args.data.adapter.type,
        name = args.data.adapter.formatted_name,
        model = args.data.adapter.model,
        available_tools = evaluated_tools,
      }
    else
      adapter_cache[bufnr] = nil
    end
  end,
})

api.nvim_create_autocmd("User", {
  group = aug,
  pattern = "CodeCompanionChatClosed",
  callback = function(args)
    local bufnr = args.data.bufnr
    adapter_cache[bufnr] = nil
  end,
})

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

---Return the ACP commands to be used for completion
---@param bufnr? number Buffer number (defaults to current buffer)
---@return table
function M.acp_commands(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  -- Only show ACP commands if this buffer is using an ACP adapter
  local adapter_info = adapter_cache[bufnr]
  if not adapter_info or adapter_info.type ~= "acp" then
    return {}
  end

  local acp_commands = require("codecompanion.strategies.chat.acp.commands")
  local commands = acp_commands.get_commands_for_buffer(bufnr)
  local acp_trigger = get_acp_trigger()

  return vim
    .iter(commands)
    :map(function(cmd)
      local detail = cmd.description
      if cmd.input and cmd.input ~= vim.NIL and type(cmd.input) == "table" and cmd.input.hint then
        detail = detail .. " " .. cmd.input.hint
      end

      return {
        label = acp_trigger .. cmd.name,
        detail = detail,
        command = cmd,
        type = "acp_command",
      }
    end)
    :totable()
end

---Execute selected ACP command (insert as text, no auto-submit)
---@param selected table The selected item from the completion menu
---@return string The text to insert
function M.acp_commands_execute(selected)
  -- Return the command text with backslash trigger (will be transformed to forward slash on send)
  local text = get_acp_trigger() .. selected.command.name

  -- Add a space if the command accepts arguments
  if
    selected.command.input
    and selected.command.input ~= vim.NIL
    and type(selected.command.input) == "table"
    and selected.command.input.hint
  then
    text = text .. " "
  end

  return text
end

---Return the tools to be used for completion
---@return table
function M.tools()
  local bufnr = api.nvim_get_current_buf()
  local adapter_info = adapter_cache[bufnr]

  -- Only show tools for HTTP adapters
  if not adapter_info or adapter_info.type == "acp" then
    return {}
  end

  -- Get filtered tools configuration (this uses the cache!)
  local tools = ToolFilter.filter_enabled_tools(config.strategies.chat.tools, { adapter = adapter_info })

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

  -- Add config tools
  vim
    .iter(tools)
    :filter(function(label, value)
      return label ~= "opts" and label ~= "groups" and value.visible ~= false
    end)
    :each(function(label, v)
      local description = v.description
      if v._adapter_tool then
        description = string.format("**%s** %s", adapter_info.name, description)
      end

      table.insert(items, {
        label = trigger.tools .. label,
        name = label,
        type = "tool",
        callback = v.callback,
        detail = description,
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
