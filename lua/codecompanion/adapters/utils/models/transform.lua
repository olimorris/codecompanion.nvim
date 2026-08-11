local M = {}

---@class CodeCompanion.Adapter.ModelChoice
---@field formatted_name string
---@field meta? { context_window?: number, max_tokens?: number }
---@field opts table

---Ref: https://platform.claude.com/docs/en/api/models-list
---@param model table
---@return string id, CodeCompanion.Adapter.ModelChoice entry
function M.from_anthropic(model)
  local capabilities = model.capabilities or {}
  local thinking = capabilities.thinking or {}
  local thinking_types = thinking.types or {}

  local context_management = capabilities.context_management or {}

  local opts = {
    can_form_structured_outputs = (capabilities.structured_outputs or {}).supported or false,
    can_manage_context = (context_management.compact_20260112 or {}).supported or false,
    can_reason = thinking.supported or false,
    has_vision = (capabilities.image_input or {}).supported or false,
  }

  -- Models that only support the legacy "enabled" thinking type (no adaptive effort) still
  -- need the old `thinking = { type = "enabled" }` request shape rather than `effort`
  if
    thinking.supported
    and (thinking_types.enabled or {}).supported
    and not (thinking_types.adaptive or {}).supported
  then
    opts.legacy_reasoning = true
  end

  local effort = capabilities.effort
  if effort and effort.supported then
    local supported_efforts = {}
    for _, level in ipairs({ "low", "medium", "high", "xhigh", "max" }) do
      if effort[level] and effort[level].supported then
        table.insert(supported_efforts, level)
      end
    end
    opts.reasoning = { supported = supported_efforts }
  end

  return model.id,
    {
      formatted_name = model.display_name,
      meta = { context_window = model.max_input_tokens, max_tokens = model.max_tokens },
      opts = opts,
    }
end

---@param model table
---@return string|nil id, CodeCompanion.Adapter.ModelChoice|nil entry
function M.from_copilot(model)
  if not model.model_picker_enabled then
    return nil
  end

  local capabilities = model.capabilities or {}
  local model_type = capabilities.type
  if type(model_type) == "string" and model_type ~= "chat" then
    return nil
  end
  if type(model_type) == "table" and not vim.tbl_contains(model_type, "chat") then
    return nil
  end

  local endpoint = "completions"
  for _, supported_endpoint in ipairs(model.supported_endpoints or {}) do
    if supported_endpoint == "/responses" then
      endpoint = "responses"
      break
    end
  end

  local opts = {}
  local limits = {}
  local billing = {}

  local supports = capabilities.supports or {}
  opts.can_stream = supports.streaming or nil
  opts.can_form_structured_outputs = supports.structured_outputs or nil
  opts.can_use_tools = supports.tool_calls or nil
  opts.has_vision = supports.vision or nil

  local capability_limits = capabilities.limits
  if capability_limits then
    limits.max_output_tokens = capability_limits.max_output_tokens
    limits.max_prompt_tokens = capability_limits.max_prompt_tokens
    limits.context_window = capability_limits.max_context_window_tokens
  end

  if model.billing then
    billing.is_premium = model.billing.is_premium
    billing.multiplier = model.billing.multiplier
  end

  local description = model.name .. (billing.multiplier and (" (" .. billing.multiplier .. "x)") or "")

  return model.id,
    {
      billing = billing,
      description = description,
      endpoint = endpoint,
      formatted_name = model.name,
      limits = limits,
      meta = limits.context_window and { context_window = limits.context_window } or nil,
      opts = opts,
      vendor = model.vendor,
    }
end

---@param name string The model's name, as returned by `/api/tags`
---@param model_info table|nil The decoded body of the `/api/show` response
---@return CodeCompanion.Adapter.ModelChoice entry
function M.from_ollama(name, model_info)
  model_info = model_info or {}

  local capabilities = model_info.capabilities or {}
  local opts = {
    can_reason = vim.list_contains(capabilities, "thinking"),
    can_use_tools = vim.list_contains(capabilities, "tools"),
    has_vision = vim.list_contains(capabilities, "vision"),
  }

  local meta
  if model_info.model_info and model_info.details and model_info.details.family then
    local context_length = model_info.model_info[model_info.details.family .. ".context_length"]
    if context_length then
      meta = { context_window = context_length }
    end
  end

  return {
    formatted_name = name,
    meta = meta,
    opts = opts,
  }
end

---Ref: https://docs.mistral.ai/api/#tag/models/operation/list_models_v1_models_get
---@param model table
---@return string id, CodeCompanion.Adapter.ModelChoice entry
function M.from_mistral(model)
  local capabilities = model.capabilities or {}

  local opts = {
    can_form_structured_outputs = capabilities.function_calling or false,
    can_reason = capabilities.reasoning or false,
    can_use_tools = capabilities.function_calling or false,
    has_vision = capabilities.vision or false,
  }

  return model.id,
    {
      formatted_name = model.name,
      meta = model.max_context_length and { context_window = model.max_context_length } or nil,
      opts = opts,
    }
end

---Ref: https://openrouter.ai/docs/api-reference/list-available-models
---@param model table
---@return string id, CodeCompanion.Adapter.ModelChoice entry
function M.from_openrouter(model)
  local supported = {}
  for _, parameter in ipairs(model.supported_parameters or {}) do
    supported[parameter] = true
  end

  local opts = {
    supported_parameters = supported,
    can_form_structured_outputs = supported.structured_outputs or false,
    can_use_tools = supported.tools or false,
    can_reason = supported.reasoning or false,
    reasoning = model.reasoning and {
      default = model.reasoning.default_effort,
      supported = model.reasoning.supported_efforts,
    } or nil,
  }
  if model.architecture and model.architecture.input_modalities then
    opts.has_vision = vim.tbl_contains(model.architecture.input_modalities, "image")
  end

  return model.id,
    {
      formatted_name = model.name,
      meta = model.context_length and { context_window = model.context_length } or nil,
      opts = opts,
    }
end

return M
