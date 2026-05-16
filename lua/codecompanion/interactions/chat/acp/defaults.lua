local ACP = require("codecompanion.acp")
local log = require("codecompanion.utils.log")

local M = {}

---Resolve a value against an option's available values
---@param opt table SessionConfigOption
---@param value string
---@return string|nil
local function resolve_value(opt, value)
  local value_lower = value:lower()
  for _, val in ipairs(ACP.flatten_config_options(opt.options or {})) do
    if val.value == value then
      return val.value
    end
  end
  for _, val in ipairs(ACP.flatten_config_options(opt.options or {})) do
    if type(val.value) == "string" and val.value:lower() == value_lower then
      return val.value
    end
    if type(val.name) == "string" and val.name:lower() == value_lower then
      return val.value
    end
  end
end

---Look up an option by category from the current connection
---@param connection CodeCompanion.ACP.Connection
---@param category string
---@return table|nil
local function find_option(connection, category)
  for _, opt in ipairs(connection:get_config_options()) do
    if opt.category == category and opt.type == "select" then
      return opt
    end
  end
end

---Apply adapter-level default session config options to the active ACP session.
---@param adapter CodeCompanion.ACPAdapter
---@param connection CodeCompanion.ACP.Connection
---@return nil
function M.apply(adapter, connection)
  local adapter_defaults = adapter and adapter.defaults or {}

  -- TODO: Remove in v20.0.0 — legacy top-level `model` / `mode` fields
  local desired = {}
  if adapter_defaults.session_config_options then
    for category, value in pairs(adapter_defaults.session_config_options) do
      desired[category] = value
    end
  end
  if adapter_defaults.model and desired.model == nil then
    desired.model = adapter_defaults.model
  end
  if adapter_defaults.mode and desired.mode == nil then
    desired.mode = adapter_defaults.mode
  end

  if vim.tbl_isempty(desired) or #connection:get_config_options() == 0 then
    return
  end

  -- Set the model first as this dictates what options are available in some ACP adapters
  local ordered = {}
  if desired.model then
    table.insert(ordered, "model")
  end
  for category in pairs(desired) do
    if category ~= "model" then
      table.insert(ordered, category)
    end
  end

  -- Set the option
  for _, category in ipairs(ordered) do
    local value = desired[category]
    if type(value) == "function" then
      value = value(adapter)
    end
    if type(value) ~= "string" or value == "" then
      goto continue
    end

    local opt = find_option(connection, category)
    if not opt then
      log:warn("[acp::defaults] No config option with category `%s`", category)
      goto continue
    end

    local resolved = resolve_value(opt, value)
    if not resolved then
      log:warn("[acp::defaults] Value `%s` not available for `%s`", value, category)
      goto continue
    end

    if resolved ~= opt.currentValue then
      connection:set_config_option(opt.id, resolved)
    end

    ::continue::
  end
end

return M
