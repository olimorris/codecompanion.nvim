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

---Create an editor context module instance
---@param interaction CodeCompanion.Chat|{buffer_context: CodeCompanion.BufferContext}
---@param ctx_config table
---@param params? string
---@param target? string
---@param interaction_type? "chat"|"cli"
---@return table
local function create_module(interaction, ctx_config, params, target, interaction_type)
  interaction_type = interaction_type or "chat"

  local init = {
    Chat = interaction_type == "chat" and interaction or nil,
    buffer_context = interaction.buffer_context,
    config = ctx_config,
    params = params or (ctx_config.opts and ctx_config.opts.default_params),
    target = target,
  }

  if ctx_config.path then
    log:trace("Calling editor context: %s", ctx_config.path)
    return require_module(ctx_config.path).new(init)
  end

  -- No path means a user-defined callback
  log:trace("Calling user editor context: %s", ctx_config.name)
  return require("codecompanion.interactions.shared.editor_context.user").new(init)
end

---Render an editor context module for the chat interaction
---Checks for chat_render first (new API), falls back to apply (user-defined contexts)
---@param module table
---@return nil
local function chat_render(module)
  if module.chat_render then
    return module:chat_render()
  elseif module.apply then
    return module:apply()
  end
end

---@class CodeCompanion.EditorContext
local EditorContext = {}

---@param interaction? string The interaction type ("chat", "cli") to filter contexts by
function EditorContext.new(interaction)
  local ec = config.interactions.shared.editor_context
  local contexts = {}
  for k, v in pairs(ec) do
    if k ~= "opts" then
      local allowed = v.opts and v.opts.interactions
      if not allowed or not interaction or vim.tbl_contains(allowed, interaction) then
        contexts[k] = v
      end
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

      local module = create_module(chat, ctx_config, params, target)
      chat_render(module)

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
  local ctx_keys = vim.tbl_keys(self.editor_context)
  table.sort(ctx_keys, function(a, b)
    return #a > #b
  end)
  for _, ctx in ipairs(ctx_keys) do
    local ctx_config = self.editor_context[ctx]
    -- Delegate to the module's replace method if it has one
    if ctx_config.path then
      local ok, module = pcall(require_module, ctx_config.path)
      if ok and module.replace then
        message = module.replace(CONSTANTS.PREFIX, message, bufnr)
        goto continue
      end
    end

    -- Generic replacement: replace all forms of #{ctx...} with the ctx name
    message = regex.replace(message, self:_pattern(ctx, true, true), ctx)
    message = regex.replace(message, self:_pattern(ctx, false, true), ctx)
    message = regex.replace(message, self:_pattern(ctx, true), ctx)
    message = vim.trim(regex.replace(message, self:_pattern(ctx), ctx))

    ::continue::
  end
  return message
end

---Replace editor context tags in a message for CLI
---Tags are replaced inline with short labels and the full
---context blocks are appended after the message.
---@param message string
---@param buffer_context CodeCompanion.BufferContext
---@return string
function EditorContext:replace_cli(message, buffer_context)
  local prefix = vim.pesc(CONSTANTS.PREFIX)
  local context_blocks = {}

  -- Check if the original message is only tags (no surrounding user text)
  local stripped = message
  for ctx, _ in pairs(self.editor_context) do
    local escaped_ctx = vim.pesc(ctx)
    stripped = stripped:gsub(prefix .. "{" .. escaped_ctx .. ":[^}]*}{[^}]*}", "")
    stripped = stripped:gsub(prefix .. "{" .. escaped_ctx .. ":[^}]*}", "")
    stripped = stripped:gsub(prefix .. "{" .. escaped_ctx .. "}{[^}]*}", "")
    stripped = stripped:gsub(prefix .. "{" .. escaped_ctx .. "}", "")
  end
  local context_only = vim.trim(stripped) == ""
  local inline_labels = {}

  for ctx, ctx_config in pairs(self.editor_context) do
    local escaped_ctx = vim.pesc(ctx)

    ---Resolve a single editor context match via cli_render()
    ---@param target? string
    ---@param params? string
    ---@return string The inline label to substitute in place of the tag
    local function resolve_match(target, params)
      if (ctx_config.opts and ctx_config.opts.contains_code) and not config.can_send_code() then
        return ""
      end

      ctx_config["name"] = ctx

      if not params and ctx_config.opts and ctx_config.opts.has_params then
        params = ctx_config.opts.default_params
      end

      local interaction = { buffer_context = buffer_context }
      local module = create_module(interaction, ctx_config, params, target, "cli")

      if not module.cli_render then
        return ""
      end

      local result = module:cli_render()
      if not result then
        return ""
      end

      -- Collect the full context block
      if result.block then
        table.insert(context_blocks, result.block)
      end

      -- When the prompt is only tags, collect inline labels as fallback
      if context_only then
        if result.inline then
          table.insert(inline_labels, result.inline)
        end
        return ""
      end

      return result.inline or ""
    end

    -- #{ctx:target}{params}
    message = message:gsub(prefix .. "{" .. escaped_ctx .. ":([^}]*)}{([^}]*)}", function(target, params)
      return resolve_match(target, params)
    end)
    -- #{ctx:target}
    message = message:gsub(prefix .. "{" .. escaped_ctx .. ":([^}]*)}", function(target)
      return resolve_match(target)
    end)
    -- #{ctx}{params}
    message = message:gsub(prefix .. "{" .. escaped_ctx .. "}{([^}]*)}", function(params)
      return resolve_match(nil, params)
    end)
    -- #{ctx}
    message = message:gsub(prefix .. "{" .. escaped_ctx .. "}", function()
      return resolve_match()
    end)
  end

  if context_only then
    -- Prefer blocks when available, fall back to inline labels
    if #context_blocks > 0 then
      return table.concat(context_blocks, "\n")
    end
    if #inline_labels > 0 then
      return table.concat(inline_labels, "\n")
    end
  end

  if #context_blocks > 0 then
    return string.format(
      [[%s

%s]],
      vim.trim(message),
      table.concat(context_blocks, "\n")
    )
  end

  return vim.trim(message)
end

return EditorContext
