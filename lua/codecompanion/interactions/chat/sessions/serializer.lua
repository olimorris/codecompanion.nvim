--[[
===============================================================================
    File:       codecompanion/interactions/chat/sessions/serializer.lua
-------------------------------------------------------------------------------
    Description:
      Converts a chat to and from its on-disk form.

===============================================================================
--]]

local ToolRegistry = require("codecompanion.interactions.chat.tool_registry")
local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")
local utils = require("codecompanion.utils")

local fmt = string.format

local M = {}

M.SCHEMA_VERSION = 1

---@param messages table[]
---@return table[]
local function encode_messages(messages)
  local encoded = {}
  for _, message in ipairs(messages or {}) do
    local entry = {
      role = message.role,
      content = message.content,
    }
    if message.reasoning ~= nil then
      entry.reasoning = vim.deepcopy(message.reasoning)
    end
    if message.tools ~= nil then
      entry.tools = vim.deepcopy(message.tools)
    end
    if message.opts ~= nil then
      entry.opts = { visible = message.opts.visible }
    end
    if message.context ~= nil then
      entry.context = vim.deepcopy(message.context)
    end
    if message._meta and message._meta.tag ~= nil then
      entry._meta = { tag = message._meta.tag }
    end
    table.insert(encoded, entry)
  end
  return encoded
end

---@param registry CodeCompanion.Chat.ToolRegistry
---@return { groups: table<string, string[]>, items: string[] }
local function encode_tools(registry)
  local items = vim.tbl_keys(registry and registry.in_use or {})
  table.sort(items)
  return {
    groups = vim.deepcopy(registry and registry.groups or {}),
    items = items,
  }
end

---@param chat CodeCompanion.Chat
---@return string
local function get_cwd(chat)
  local winid = vim.fn.bufwinid(chat.bufnr)
  return winid ~= -1 and vim.fn.getcwd(winid) or vim.fn.getcwd()
end

---Build the two JSON records that make up a session on disk
---@param chat CodeCompanion.Chat
---@param opts { created_at: number, saved_at: number }
---@return { meta: table, chat: table }
function M.to_session(chat, opts)
  local adapter = chat.adapter
  local model = adapter and adapter.schema and adapter.schema.model and adapter.schema.model.default

  return {
    chat = {
      adapter = adapter and adapter.name,
      context_items = vim.deepcopy(chat.context_items or {}),
      cycle = chat.cycle,
      messages = encode_messages(chat.messages),
      model = model,
      schema_version = M.SCHEMA_VERSION,
      settings = chat.settings and vim.deepcopy(chat.settings) or nil,
      tools = encode_tools(chat.tool_registry),
    },
    meta = {
      cwd = get_cwd(chat),
      created_at = opts.created_at,
      saved_at = opts.saved_at,
      schema_version = M.SCHEMA_VERSION,
      title = chat.title,
    },
  }
end

---Resolve the saved adapter, falling back to the default
---@param saved_chat table
---@return string|table
local function resolve_adapter(saved_chat)
  local name = saved_chat.adapter
  if name and config.adapters.http and config.adapters.http[name] then
    -- The model has to be passed through `resolve`; `set_model` reads the adapter's own default
    return adapters.resolve(name, { model = saved_chat.model })
  end

  if name then
    utils.notify(fmt("Adapter '%s' is no longer configured. Using the default adapter", name), vim.log.levels.WARN)
  end

  return config.interactions.chat.adapter
end

---Convert a decoded `_chat.json` into args for `Chat.new`
---@param saved_chat table
---@return table
function M.to_chat_args(saved_chat)
  return {
    adapter = resolve_adapter(saved_chat),
    messages = encode_messages(saved_chat.messages),
    settings = saved_chat.settings,
  }
end

---@param chat CodeCompanion.Chat
---@param name string
---@return table|nil
local function resolve_schema(chat, name)
  local tool_config = config.interactions.chat.tools[name]
  if not tool_config then
    return nil
  end

  if tool_config._adapter_tool == true then
    return { name = name, description = tool_config.description or "", _meta = { adapter_tool = true } }
  end

  local resolved = chat.tools.resolve(tool_config)
  return resolved and resolved.schema or nil
end

---Restore the saved tools against the config
---@param chat CodeCompanion.Chat
---@param tools { groups?: table<string, string[]>, items?: string[] }
---@return nil
function M.restore_tools(chat, tools)
  tools = tools or {}
  local registry = chat.tool_registry
  local missing = {}

  for _, name in ipairs(tools.items or {}) do
    local schema = resolve_schema(chat, name)
    if schema then
      registry.in_use[name] = true
      registry.schemas[ToolRegistry.tool_id(name)] = schema
    else
      table.insert(missing, name)
    end
  end

  for group, members in pairs(tools.groups or {}) do
    if config.interactions.chat.tools.groups[group] then
      registry.groups[group] = vim.tbl_filter(function(name)
        return registry.in_use[name] == true
      end, members)
    else
      table.insert(missing, group)
    end
  end

  if not vim.tbl_isempty(missing) then
    utils.notify(
      fmt("These tools are no longer configured and were not restored: %s", table.concat(missing, ", ")),
      vim.log.levels.WARN
    )
  end
end

return M
