local adapter_utils = require("codecompanion.adapters.utils")
local config = require("codecompanion.config")

local fmt = string.format

local M = {}

---@param model string|table
---@return string
local function get_model_id(model)
  return type(model) == "table" and (model.id or model.modelId) or model
end

---@param model string|table
---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter }
---@return string
local function get_model_label(model, opts)
  if type(model) ~= "table" then
    return model
  end
  if opts.adapter.type == "acp" then
    return model.description and fmt("%s - %s", model.name, model.description) or model.name
  end
  return model.description or model.formatted_name or model.id
end

---Get list of available adapters
---@param current_adapter string The currently selected adapter
---@return table List of adapter names with current adapter first
function M.get_adapters_list(current_adapter)
  local adapters =
    vim.tbl_deep_extend("force", {}, vim.deepcopy(config.adapters.acp), vim.deepcopy(config.adapters.http))

  local hidden = config.adapters.http.opts.hidden

  local adapters_list = vim
    .iter(adapters)
    :filter(function(adapter)
      -- Clear out the acp and http keys
      return adapter ~= "acp"
        and adapter ~= "http"
        and adapter ~= "extend"
        and adapter ~= "opts"
        and adapter ~= current_adapter
        and not hidden[adapter]
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
function M.list_http_models(adapter)
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

  local current_model_id = adapter_utils.resolve_model(adapter)

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
      if type(key) == "string" and value == nil then
        -- `models` is already a list
        return key
      end
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

---Pick an adapter, with the current one first and marked
---@param opts { current: string, on_choice: fun(name?: string) }
---@return nil
function M.select_adapter(opts)
  vim.ui.select(M.get_adapters_list(opts.current), {
    prompt = "Select Adapter",
    kind = "codecompanion.nvim",
    format_item = function(name)
      return (name == opts.current and "* " or "  ") .. name
    end,
  }, opts.on_choice)
end

---Pick one of the adapter's models, calling `on_choice` with nil when there's only one
---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter, acp_models?: { availableModels: table[], currentModelId: string }, on_choice: fun(model_id?: string) }
---@return nil
function M.select_model(opts)
  local models, current_id
  if opts.adapter.type == "acp" then
    models = opts.acp_models and opts.acp_models.availableModels
    current_id = opts.acp_models and opts.acp_models.currentModelId
  else
    ---@diagnostic disable-next-line: param-type-mismatch
    models = M.list_http_models(opts.adapter)
    current_id = models and get_model_id(models[1])
  end

  if not models or #models < 2 then
    return opts.on_choice(nil)
  end

  vim.ui.select(models, {
    prompt = "Select Model",
    kind = "codecompanion.nvim",
    format_item = function(model)
      return (get_model_id(model) == current_id and "* " or "  ") .. get_model_label(model, opts)
    end,
  }, function(model)
    opts.on_choice(model and get_model_id(model))
  end)
end

return M
