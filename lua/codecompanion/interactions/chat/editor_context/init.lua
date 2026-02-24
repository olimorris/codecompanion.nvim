local config = require("codecompanion.config")
local triggers = require("codecompanion.triggers")

local log = require("codecompanion.utils.log")
local regex = require("codecompanion.utils.regex")

local CONSTANTS = {
  PREFIX = triggers.mappings.editor_context,
}

---Check a message for any parameters that have been given to the context
---@param message table
---@param ctx string
---@param target? string If provided, look for params after this specific target
---@return string|nil
local function find_params(message, ctx, target)
  local pattern
  if target then
    pattern = CONSTANTS.PREFIX .. "{" .. ctx .. ":" .. vim.pesc(target) .. "}{([^}]*)}"
  else
    pattern = CONSTANTS.PREFIX .. "{" .. ctx .. "}{([^}]*)}"
  end

  local params = message.content:match(pattern)
  if params then
    log:trace("Params found for editor context: %s", params)
    return params
  end
  return nil
end

---Require an editor context module by its dot-separated path
---@param path string
---@return table
local function require_module(path)
  -- Try as a built-in module first, then as a user-provided path
  local ok, module = pcall(require, "codecompanion." .. path)
  if ok then
    return module
  end

  return require(path)
end

---@param chat CodeCompanion.Chat
---@param ctx_config table
---@param params? string
---@param target? string
---@return table
local function resolve(chat, ctx_config, params, target)
  local init = {
    Chat = chat,
    config = ctx_config,
    params = params or (ctx_config.opts and ctx_config.opts.default_params),
    target = target,
  }

  if ctx_config.path then
    log:trace("Calling editor context: %s", ctx_config.path)
    return require_module(ctx_config.path).new(init):apply()
  end

  -- No path means a user-defined callback
  log:trace("Calling user editor context: %s", ctx_config.name)
  return require("codecompanion.interactions.chat.editor_context.user").new(init):apply()
end

---@class CodeCompanion.EditorContext
local EditorContext = {}

function EditorContext.new()
  local ec = config.interactions.chat.editor_context
  local contexts = {}
  for k, v in pairs(ec) do
    if k ~= "opts" then
      contexts[k] = v
    end
  end

  local self = setmetatable({
    editor_context = contexts,
  }, { __index = EditorContext })

  return self
end

---Creates a regex pattern to match editor context in a message
---@param ctx string The editor context name to create a pattern for
---@param include_params? boolean Whether to include parameters in the pattern
---@param include_display_option? boolean Whether to include display options in the pattern
---@return string The compiled regex pattern
function EditorContext:_pattern(ctx, include_params, include_display_option)
  local base_pattern = CONSTANTS.PREFIX .. "{" .. ctx

  if include_display_option then
    base_pattern = base_pattern .. ":[^}]*"
  end

  base_pattern = base_pattern .. "}"

  if include_params then
    base_pattern = base_pattern .. "{[^}]*}"
  end

  return base_pattern
end

---Check a message for editor context and return all instances
---@param message table
---@return table|nil
function EditorContext:find(message)
  if not message.content then
    return nil
  end

  local found = {}
  local content = message.content
  local prefix = vim.pesc(CONSTANTS.PREFIX)

  for ctx, _ in pairs(self.editor_context) do
    local escaped_ctx = vim.pesc(ctx)

    -- Match #{ctx:target} (with optional {params})
    for target in content:gmatch(prefix .. "{" .. escaped_ctx .. ":([^}]*)}") do
      table.insert(found, { ctx = ctx, target = target })
    end

    -- Match #{ctx} (with optional {params}) — no overlap with the above
    -- because #{ctx:target} has a : after ctx, not a }
    for _ in content:gmatch(prefix .. "{" .. escaped_ctx .. "}") do
      table.insert(found, { ctx = ctx, target = nil })
    end
  end

  if #found == 0 then
    return nil
  end

  return found
end

---Parse a message to detect if it contains any editor context
---@param chat CodeCompanion.Chat
---@param message table
---@return boolean
function EditorContext:parse(chat, message)
  local instances = self:find(message)
  if instances then
    for _, instance in ipairs(instances) do
      local ctx = instance.ctx
      local ctx_config = self.editor_context[ctx]
      log:debug("Editor context found: %s (target: %s)", ctx, instance.target or "none")

      ctx_config["name"] = ctx

      if (ctx_config.opts and ctx_config.opts.contains_code) and not config.can_send_code() then
        log:warn("Sending of code has been disabled")
        goto continue
      end

      local target = instance.target
      local params = nil

      -- Check for regular params
      if ctx_config.opts and ctx_config.opts.has_params then
        params = find_params(message, ctx, target)
      end

      resolve(chat, ctx_config, params, target)

      ::continue::
    end

    return true
  end

  return false
end

---Replace editor context in a given message
---@param message string
---@param bufnr number
---@return string
function EditorContext:replace(message, bufnr)
  for ctx, ctx_config in pairs(self.editor_context) do
    -- Delegate to the module's replace method if it has one
    if ctx_config.path then
      local ok, module = pcall(require_module, ctx_config.path)
      if ok and module.replace then
        message = module.replace(CONSTANTS.PREFIX, message, bufnr)
        goto continue
      end
    end

    -- Generic replacement: strip all forms of #{ctx...}
    message = regex.replace(message, self:_pattern(ctx, true, true), "")
    message = regex.replace(message, self:_pattern(ctx, false, true), "")
    message = regex.replace(message, self:_pattern(ctx, true), "")
    message = vim.trim(regex.replace(message, self:_pattern(ctx), ""))

    ::continue::
  end
  return message
end

return EditorContext
