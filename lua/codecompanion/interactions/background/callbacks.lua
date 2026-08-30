local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local M = {}

---Resolve a background action module from a given path
---@param path string The path to the module
---@return table|nil The loaded action module or nil on failure
function M.resolve(path)
  return utils.resolve({ value = path, source = "background::callbacks" })
end

---Execute an action
---@param action_config { path: string, adapter?: CodeCompanion.HTTPAdapter|string }
---@param chat CodeCompanion.Chat The chat instance
---@param opts? { deregister: fun() }
---@return nil
local function execute_action(action_config, chat, opts)
  local path = action_config.path
  local action = M.resolve(path)
  if not action then
    return log:error("[background::callbacks] File `%s` could not be found", path)
  end
  if not action.request then
    return log:error("[background::callbacks] File `%s` does not have a request function", path)
  end

  -- Per-action adapter overrides the shared background adapter
  local Background = require("codecompanion.interactions.background")
  local background = Background.new({
    adapter = action_config.adapter or config.interactions.background.adapter,
  })

  if not background then
    return log:debug("[background::callbacks] Failed to create instance for action: %s", path)
  end

  -- Don't block the main thread
  vim.schedule(function()
    local ok, result = pcall(action.request, background, chat, { deregister = opts and opts.deregister })
    if not ok then
      log:debug("[background::callbacks] Error executing action %s: %s", path, result)
    end
  end)
end

---Register background callbacks for a chat instance
---@param chat CodeCompanion.Chat The chat instance to register callbacks for
---@return nil
function M.register_chat_callbacks(chat)
  local background_config = config.interactions.background.chat

  if not background_config or background_config.opts.enabled == false then
    return
  end

  -- Register each action as its own callback so it can deregister itself once done
  for event, event_config in pairs(background_config.callbacks) do
    if event_config.enabled and event_config.actions then
      for _, action in ipairs(event_config.actions) do
        local action_config = type(action) == "string" and { path = action } or action
        local callback
        callback = function(c)
          execute_action(action_config, c, {
            deregister = function()
              c:remove_callback(event, callback)
            end,
          })
        end
        chat:add_callback(event, callback)
      end

      log:debug("[background::callbacks] Registered %d actions for chat event: %s", #event_config.actions, event)
    end
  end
end

return M
