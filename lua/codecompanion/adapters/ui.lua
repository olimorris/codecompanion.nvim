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

---Adapter names, with the current adapter first
---@param current_adapter string
---@return string[]
function M.get_adapters_list(current_adapter)
  local adapters =
    vim.tbl_deep_extend("force", {}, vim.deepcopy(config.adapters.acp), vim.deepcopy(config.adapters.http))

  local hidden = config.adapters.http.opts.hidden

  local adapters_list = vim
    .iter(adapters)
    :filter(function(adapter)
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

---Turn a list or map of model choices into a list, giving each table an `id`
---@param choices table
---@return (string|table)[]
local function list_choices(choices)
  local models = {}
  for key, model in pairs(choices) do
    if type(model) == "table" and not model.id then
      model.id = key
    end
    table.insert(models, model)
  end
  return models
end

---The adapter's models, sorted with the current model first
---@param adapter CodeCompanion.HTTPAdapter
---@return (string|table)[]|nil
function M.list_http_models(adapter)
  if not config.adapters.http.opts.show_model_choices then
    return nil
  end

  local choices = adapter.schema.model.choices
  if type(choices) == "function" then
    -- When user explicitly wants to change models, force token creation
    choices = choices(adapter, { async = false })
  end
  if not choices or vim.tbl_count(choices) < 2 then
    return nil
  end

  local current_id = adapter_utils.resolve_model(adapter)
  local current, others = nil, {}
  for _, model in ipairs(list_choices(choices)) do
    if get_model_id(model) == current_id then
      current = model
    else
      table.insert(others, model)
    end
  end

  table.sort(others, function(a, b)
    local name_a = type(a) == "table" and (a.formatted_name or a.id) or a
    local name_b = type(b) == "table" and (b.formatted_name or b.id) or b
    return name_a < name_b
  end)
  if current then
    table.insert(others, 1, current)
  end

  return others
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
