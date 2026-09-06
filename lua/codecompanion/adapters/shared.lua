local adapter_utils = require("codecompanion.adapters.utils")
local log = require("codecompanion.utils.log")

local M = {}

---Replace roles in the messages with the adapter's defined roles
---@param adapter table
---@param messages table
---@return table
function M.map_roles(adapter, messages)
  return adapter_utils.map_roles(adapter.roles, messages)
end

---Deep-merge a user's extend table onto a resolved adapter
---@param adapter table
---@param opts { extend?: table, key?: string }
---@return table
function M.apply_extend(adapter, opts)
  opts = opts or {}

  local patch = opts.key and opts.extend and opts.extend[opts.key]
  if type(patch) ~= "table" then
    return adapter
  end

  for key, value in pairs(patch) do
    if type(value) == "table" and type(adapter[key]) == "table" then
      adapter[key] = vim.tbl_deep_extend("force", adapter[key], value)
    else
      adapter[key] = value
    end
  end

  return adapter
end

---Read a field from an adapter's meta data
---@param adapter CodeCompanion.HTTPAdapter
---@param fields string[]
---@return number|nil
local function from_model_meta(adapter, fields)
  local function pick(meta)
    if type(meta) ~= "table" then
      return nil
    end
    for _, field in ipairs(fields) do
      if meta[field] then
        return meta[field]
      end
    end
  end

  local value = adapter.model and pick(adapter.model.meta)
  if value then
    return value
  end

  local model = adapter.schema and adapter.schema.model and adapter.schema.model.default
  if type(model) == "function" then
    local ok, resolved = pcall(model, adapter)
    if not ok then
      log:debug("[Context Window] Failed to resolve model name for `%s` adapter: %s", adapter.name, resolved)
      return nil
    end
    model = resolved
  end

  local choices = adapter.schema and adapter.schema.model and adapter.schema.model.choices
  if type(choices) == "function" then
    local ok, resolved = pcall(choices, adapter, { async = true })
    if not ok then
      log:debug("[Context Window] Failed to resolve model choices for `%s` adapter: %s", adapter.name, resolved)
      return nil
    end
    choices = resolved
  end

  if type(choices) == "table" and model and choices[model] then
    return pick(choices[model].meta)
  end

  return nil
end

---Resolve the context window for the current model
---@param adapter CodeCompanion.HTTPAdapter
---@return number|nil
function M.context_window(adapter)
  return from_model_meta(adapter, { "context_window" })
end

---Resolve the largest prompt the current model will accept
---@param adapter CodeCompanion.HTTPAdapter
---@return number|nil
function M.input_limit(adapter)
  return from_model_meta(adapter, { "max_prompt_tokens", "context_window" })
end

---Whether the provider compacts its own context server-side for the current model
---@param adapter CodeCompanion.HTTPAdapter
---@return boolean
function M.manages_own_context(adapter)
  if not adapter or not adapter.opts or adapter.opts.compaction == false then
    return false
  end

  -- A number of adapters are dynamic, and their capabilities are cached.
  -- So there's a small chance that we need to refresh the cache,
  -- which might require re-authentication or reauthorization
  local ok, model = pcall(adapter_utils.model_choice, adapter, { async = true })
  if not ok then
    log:debug("[Context Management] Failed to resolve model for `%s` adapter: %s", adapter.name, model)
    return false
  end

  return (model and model.opts and model.opts.can_manage_context) == true
end

return M
