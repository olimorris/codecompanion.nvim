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
---@param opts { extend?: table, config_key?: string }
---@return table
function M.apply_extend(adapter, opts)
  opts = opts or {}

  local patch = opts.config_key and opts.extend and opts.extend[opts.config_key]
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

---Resolve the context window for the current model
---@param adapter CodeCompanion.HTTPAdapter
---@return number|nil
function M.context_window(adapter)
  if adapter.model and adapter.model.meta and adapter.model.meta.context_window then
    return adapter.model.meta.context_window
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

  if type(choices) == "table" and model and choices[model] and choices[model].meta then
    return choices[model].meta.context_window
  end

  return nil
end

return M
