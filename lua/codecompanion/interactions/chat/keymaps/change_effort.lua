local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local M = {}

---Schema keys, most specific first, that adapters use to expose reasoning effort
M.effort_keys = { "effort", "reasoning.effort", "reasoning_effort" }

---Read a possibly-nested value from a table using a dotted key
---@param tbl table
---@param key string
---@return any
local function get_nested(tbl, key)
  local current = tbl
  for segment in key:gmatch("[^.]+") do
    if type(current) ~= "table" then
      return nil
    end
    current = current[segment]
  end
  return current
end

---Write a possibly-nested value into a table using a dotted key
---@param tbl table
---@param key string
---@param value any
---@return nil
local function set_nested(tbl, key, value)
  local segments = {}
  for segment in key:gmatch("[^.]+") do
    table.insert(segments, segment)
  end
  local current = tbl
  for i = 1, #segments - 1 do
    if type(current[segments[i]]) ~= "table" then
      current[segments[i]] = {}
    end
    current = current[segments[i]]
  end
  current[segments[#segments]] = value
end

---Find the effort schema entry for the adapter, respecting its `enabled` gate
---@param adapter CodeCompanion.HTTPAdapter
---@return string|nil key, table|nil schema_entry
function M.find_effort_schema(adapter)
  local schema = adapter.schema or {}
  for _, key in ipairs(M.effort_keys) do
    local entry = schema[key]
    if entry then
      local enabled = entry.enabled
      if type(enabled) == "function" and not enabled(adapter) then
        return nil
      end
      return key, entry
    end
  end
  return nil
end

---Resolve the list of effort levels the current model supports
---@param adapter CodeCompanion.HTTPAdapter
---@param schema_entry table
---@return string[]
local function resolve_levels(adapter, schema_entry)
  local levels = schema_entry.choices
  if type(levels) == "function" then
    levels = levels(adapter)
  end
  if type(levels) ~= "table" or vim.tbl_isempty(levels) then
    return { "low", "medium", "high", "xhigh", "max" }
  end
  return levels
end

---Resolve the currently selected effort level
---@param chat CodeCompanion.Chat
---@param adapter CodeCompanion.HTTPAdapter
---@param key string
---@param schema_entry table
---@return string|nil
local function resolve_current(chat, adapter, key, schema_entry)
  local current = get_nested(chat.settings or {}, key)
  if current ~= nil then
    return current
  end
  local default = schema_entry.default
  if type(default) == "function" then
    return default(adapter)
  end
  return default
end

---Build vim.ui.select options that mark the current level
---@param current string|nil
---@return table
local function select_opts(current)
  return {
    prompt = "Select Effort",
    kind = "codecompanion.nvim",
    format_item = function(item)
      if current == item then
        return "* " .. item
      end
      return "  " .. item
    end,
  }
end

---Main callback for the change_effort keymap
---@param chat CodeCompanion.Chat
---@return nil
function M.callback(chat)
  if config.display.chat.show_settings then
    return utils.notify(
      "Effort can't be changed when `display.chat.show_settings = true`",
      vim.log.levels.WARN
    )
  end
  if chat.adapter.type ~= "http" then
    return utils.notify("Effort can only be changed for HTTP adapters", vim.log.levels.WARN)
  end

  local adapter = chat.adapter
  ---@cast adapter CodeCompanion.HTTPAdapter

  local key, schema_entry = M.find_effort_schema(adapter)
  if not key or not schema_entry then
    return utils.notify("The current model does not support a reasoning effort setting", vim.log.levels.WARN)
  end

  local levels = resolve_levels(adapter, schema_entry)
  local current = resolve_current(chat, adapter, key, schema_entry)

  vim.ui.select(levels, select_opts(current), function(selected)
    if not selected then
      return
    end
    chat.settings = chat.settings or {}
    set_nested(chat.settings, key, selected)
    log:debug("Effort set to `%s` for `%s`", selected, key)
    return utils.notify(string.format("Effort set to `%s`", selected), vim.log.levels.INFO)
  end)
end

return M
