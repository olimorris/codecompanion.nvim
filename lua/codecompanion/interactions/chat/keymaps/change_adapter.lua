local config = require("codecompanion.config")
local utils = require("codecompanion.utils")

local M = {}

---Create options for vim.ui.select with formatting
---@param prompt string The prompt to display
---@param conditional string The item to mark as current
---@return table
local function select_opts(prompt, conditional)
  return {
    prompt = prompt,
    kind = "codecompanion.nvim",
    format_item = function(item)
      if conditional == item then
        return "* " .. item
      end
      return "  " .. item
    end,
  }
end

---Get list of available adapters
---@param current_adapter string The currently selected adapter
---@return table List of adapter names with current adapter first
function M.get_adapters_list(current_adapter)
  local adapters =
    vim.tbl_deep_extend("force", {}, vim.deepcopy(config.adapters.acp), vim.deepcopy(config.adapters.http))

  local adapters_list = vim
    .iter(adapters)
    :filter(function(adapter)
      -- Clear out the acp and http keys
      return adapter ~= "opts" and adapter ~= "acp" and adapter ~= "http" and adapter ~= current_adapter
    end)
    :map(function(adapter, _)
      return adapter
    end)
    :totable()

  table.sort(adapters_list)
  table.insert(adapters_list, 1, current_adapter)

  return adapters_list
end

---Get list of available models for an adapter
---@param adapter CodeCompanion.HTTPAdapter
---@return table|nil
function M.get_models_list(adapter)
  local models = adapter.schema.model.choices

  -- Check if we should show model choices or just the default
  local show_choices = config.adapters
    and config.adapters.http
    and config.adapters.http.opts
    and config.adapters.http.opts.show_model_choices

  if not show_choices then
    models = { adapter.schema.model.default }
  end
  if type(models) == "function" then
    -- When user explicitly wants to change models, force token creation
    models = models(adapter, { async = false })
  end
  if not models or vim.tbl_count(models) < 2 then
    return nil
  end

  local current_model_id = adapter.schema.model.default
  if type(current_model_id) == "function" then
    current_model_id = current_model_id(adapter)
  end

  local current_model = nil

  for _, model_str in ipairs(models) do
    if model_str == current_model_id then
      current_model = model_str
      break
    end
  end

  if not current_model and models[current_model_id] then
    current_model = models[current_model_id]
    -- If it's a table without an id, create one
    if type(current_model) == "table" and not current_model.id then
      current_model.id = current_model_id
    end
  end

  local models_list = vim
    .iter(models)
    :map(function(key, value)
      if type(value) == "table" and not value.id then
        value.id = key
      end
      return value
    end)
    :filter(function(model)
      local model_id = type(model) == "table" and model.id or model
      return model_id ~= current_model_id
    end)
    :totable()

  table.sort(models_list, function(a, b)
    local id_a = type(a) == "table" and (a.formatted_name or a.id) or a
    local id_b = type(b) == "table" and (b.formatted_name or b.id) or b
    return id_a < id_b
  end)

  if current_model then
    table.insert(models_list, 1, current_model)
  end

  return models_list
end

---Get list of available commands for an ACP adapter
---@param adapter CodeCompanion.ACPAdapter
---@return table|nil
function M.get_commands_list(adapter)
  local commands = adapter.commands
  if not commands or vim.tbl_count(commands) < 2 then
    return nil
  end

  local commands_list = vim
    .iter(commands)
    :map(function(key, _)
      if type(key) == "string" then
        return key
      end
    end)
    :filter(function(key)
      return key ~= "selected"
    end)
    :totable()

  table.sort(commands_list)

  return commands_list
end

---Update system prompt after adapter change
---@param chat CodeCompanion.Chat
function M.update_system_prompt(chat)
  local system_prompt = config.interactions.chat.opts.system_prompt
  if type(system_prompt) == "function" then
    if chat.messages[1] and chat.messages[1].role == "system" then
      chat.messages[1].content = system_prompt(chat:make_system_prompt_ctx())
    end
  end
end

---Handle model selection for HTTP adapters
---@param chat CodeCompanion.Chat
---@return nil
function M.select_model(chat)
  local models_list = M.get_models_list(chat.adapter)
  if not models_list then
    return
  end

  local current_model = models_list[1]

  local function get_model_id(model)
    return type(model) == "table" and model.id or model
  end

  local current_id = get_model_id(current_model)

  local opts = {
    prompt = "Select Model",
    kind = "codecompanion.nvim",
    format_item = function(model)
      local model_id = get_model_id(model)
      local display

      if type(model) == "table" then
        display = model.description or model.formatted_name or model.id or "Unknown"
      else
        display = model
      end

      -- Mark the current model
      if model_id == current_id then
        return "* " .. display
      end
      return "  " .. display
    end,
  }

  vim.ui.select(models_list, opts, function(selected_model)
    if not selected_model then
      return
    end
    local model_id = get_model_id(selected_model)
    chat:apply_model(model_id)
  end)
end

---Handle command selection for ACP adapters
---@param chat CodeCompanion.Chat
---@return nil
function M.select_command(chat)
  local commands_list = M.get_commands_list(chat.adapter)
  if not commands_list then
    return
  end

  vim.ui.select(commands_list, select_opts("Select a Command", commands_list[1]), function(selected_command)
    if not selected_command then
      return
    end
    local selected = chat.adapter.commands[selected_command]
    chat.adapter.commands.selected = selected
    utils.fire("ChatModel", { bufnr = chat.bufnr, model = selected })
    chat:update_metadata()
  end)
end

---Main callback for the change_adapter keymap
---@param chat CodeCompanion.Chat
---@return nil
function M.callback(chat)
  if config.display.chat.show_settings then
    return utils.notify("Adapter can't be changed when `display.chat.show_settings = true`", vim.log.levels.WARN)
  end

  local current_adapter = chat.adapter.name
  local adapters_list = M.get_adapters_list(current_adapter)

  vim.ui.select(adapters_list, select_opts("Select Adapter", current_adapter), function(selected_adapter)
    if not selected_adapter then
      return
    end

    if current_adapter ~= selected_adapter then
      chat.acp_connection = nil
      chat:change_adapter(selected_adapter)
    end

    -- Only force a system prompt update if the user isn't ignoring it. This
    -- occurs when a user has initiated a chat from the prompt library
    if not chat.opts.ignore_system_prompt then
      M.update_system_prompt(chat)
    end

    if chat.adapter.type == "http" then
      M.select_model(chat)
    end

    if chat.adapter.type == "acp" then
      M.select_command(chat)
    end
  end)
end

return M
