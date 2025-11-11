local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

---Execute a background action
---@param action_path string The path to the action module (e.g., "interactions.background.catalog.chat_make_title")
---@param chat CodeCompanion.Chat The chat instance
---@return nil
local function execute_action(action_path, chat)
  local ok, action = pcall(require, "codecompanion." .. action_path)
  if not ok then
    log:error("[Background] Failed to load action module: %s", action_path)
    return
  end

  if not action.request then
    log:error("[Background] Action module %s does not have a request function", action_path)
    return
  end

  -- Create a background instance using the configured adapter
  local Background = require("codecompanion.interactions.background")
  local background_config = config.interactions.background
  local background = Background.new({
    adapter = background_config.adapter,
  })

  if not background then
    log:error("[Background] Failed to create background instance for action: %s", action_path)
    return
  end

  -- Execute the action asynchronously to avoid blocking the UI
  vim.schedule(function()
    local ok, result = pcall(action.request, background, chat)
    if not ok then
      log:error("[Background] Error executing action %s: %s", action_path, result)
    else
      log:debug("[Background] Action %s completed successfully", action_path)
    end
  end)
end

---Register background callbacks for a chat instance
---@param chat CodeCompanion.Chat The chat instance to register callbacks for
---@return nil
function M.register_chat_callbacks(chat)
  local callbacks_config = config.interactions.background.callbacks

  if not callbacks_config or not callbacks_config.chat.opts.enabled then
    return
  end
  if not callbacks_config.chat then
    return
  end

  -- Register callbacks for each configured event
  for event, event_config in pairs(callbacks_config.chat) do
    if event_config.enabled and event_config.actions then
      -- Register a callback for this event
      chat:add_callback(event, function(c)
        log:debug("[Background] Executing %d actions for event: %s", #event_config.actions, event)

        -- Execute each action for this event
        for _, action_path in ipairs(event_config.actions) do
          execute_action(action_path, c)
        end
      end)

      log:debug("[Background] Registered %d actions for chat event: %s", #event_config.actions, event)
    end
  end
end

return M
