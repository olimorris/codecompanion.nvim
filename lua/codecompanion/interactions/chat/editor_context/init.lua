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
    -- #{ctx:target}{params}
    pattern = CONSTANTS.PREFIX .. "{" .. ctx .. ":" .. vim.pesc(target) .. "}{([^}]*)}"
  else
    -- #{ctx}{params}
    pattern = CONSTANTS.PREFIX .. "{" .. ctx .. "}{([^}]*)}"
  end

  local params = message.content:match(pattern)
  if params then
    log:trace("Params found for editor context: %s", params)
    return params
  end
  return nil
end

---@param chat CodeCompanion.Chat
---@param ctx_config table
---@param params? string
---@param target? string
---@return table
local function resolve(chat, ctx_config, params, target)
  if type(ctx_config.callback) == "string" then
    local splits = vim.split(ctx_config.callback, ".", { plain = true })
    local path = table.concat(splits, ".", 1, #splits - 1)
    local ctx = splits[#splits]

    local ok, module = pcall(require, "codecompanion." .. path .. "." .. ctx)

    local init = {
      Chat = chat,
      config = ctx_config,
      params = params or (ctx_config.opts and ctx_config.opts.default_params),
      target = target,
    }

    -- User is using a custom callback
    if not ok then
      log:trace("Calling editor context: %s", path .. "." .. ctx)
      return require(path .. "." .. ctx).new(init):output()
    end

    log:trace("Calling editor context: %s", path .. "." .. ctx)
    return module.new(init):output()
  end

  return require("codecompanion.interactions.chat.editor_context.user")
    .new({
      Chat = chat,
      config = ctx_config,
      params = params,
      target = target,
    })
    :output()
end

---@class CodeCompanion.EditorContext
local EditorContext = {}

function EditorContext.new()
  local self = setmetatable({
    editor_context = config.interactions.chat.editor_context,
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

  for ctx, _ in pairs(self.editor_context) do
    local display_pattern = CONSTANTS.PREFIX .. "{" .. ctx .. ":([^}]*)}"
    for target in content:gmatch(display_pattern) do
      table.insert(found, {
        ctx = ctx,
        target = target,
      })
    end

    -- Check for regular syntax (#{ctx}) - but avoid duplicating display option matches
    local regular_pattern = CONSTANTS.PREFIX .. "{" .. ctx .. "}"
    local start_pos = 1
    while true do
      local match_start, match_end = content:find(regular_pattern, start_pos, true)
      if not match_start then
        break
      end

      -- Make sure this isn't part of a display option by checking if there's a colon before the brace
      local char_before_brace = content:sub(match_end - 1, match_end - 1)
      if char_before_brace ~= ":" then
        table.insert(found, {
          ctx = ctx,
          target = nil,
        })
      end

      start_pos = match_end + 1
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
  for ctx, _ in pairs(self.editor_context) do
    -- The buffer context is unique because it can take parameters which need to be handled
    -- TODO: Potentially extract this to its own module if more editor context items have parameters
    if ctx:match("^buffer") then
      message =
        require("codecompanion.interactions.chat.editor_context.buffer").replace(CONSTANTS.PREFIX, message, bufnr)
    else
      -- Remove display option syntax first
      message = regex.replace(message, self:_pattern(ctx, true, true), "")
      message = regex.replace(message, self:_pattern(ctx, false, true), "")

      -- Then remove regular syntax
      message = regex.replace(message, self:_pattern(ctx, true), "")
      message = vim.trim(regex.replace(message, self:_pattern(ctx), ""))
    end
  end
  return message
end

return EditorContext
