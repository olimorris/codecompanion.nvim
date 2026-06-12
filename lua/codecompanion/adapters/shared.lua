local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")

local M = {}

---Replace roles in the messages with the adapter's defined roles
---@param adapter table
---@param messages table
---@return table
function M.map_roles(adapter, messages)
  return adapter_utils.map_roles(adapter.roles, messages)
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
