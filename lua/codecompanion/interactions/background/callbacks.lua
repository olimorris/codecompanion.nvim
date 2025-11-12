local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

---Resolve a callback module from a given path
---@param path string The path to the module
---@return table|nil The loaded action module or nil on failure
local function resolve(path)
  local ok, action = pcall(require, "codecompanion." .. path)
  if ok then
    return action
  end

  -- Load the tool from the user's config using a module path
  ok, action = pcall(require, path)
  if ok then
    return action
  end

  -- Try loading the tool from the user's config using a file path
  local action, err = loadfile(path)
  if err then
    return
  end

  if action then
    return action()
  end
end

---Execute an action
---@param path string The path to the module
---@param chat CodeCompanion.Chat The chat instance
---@return nil
local function execute_action(path, chat)
  local action = resolve(path)
  if not action then
    return log:error("[background::callbacks] File `%s` could not be found", path)
  end
  if not action.request then
    return log:error("[background::callbacks] File `%s` does not have a request function", path)
  end

  -- Create a background instance using the configured adapter
  local Background = require("codecompanion.interactions.background")
  local background_config = config.interactions.background
  local background = Background.new({
    adapter = background_config.adapter,
  })

  if not background then
    return log:debug("[background::callbacks] Failed to create instance for action: %s", path)
  end

  -- Don't block the main thread
  vim.schedule(function()
    local ok, result = pcall(action.request, background, chat)
    if not ok then
      log:debug("[background::callbacks] Error executing action %s: %s", path, result)
    else
      log:debug("[background::callbacks] Action %s completed successfully", path)
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
      chat:add_callback(event, function(c)
        log:debug("[background::callbacks] Executing %d actions for event: %s", #event_config.actions, event)

        for _, path in ipairs(event_config.actions) do
          execute_action(path, c)
        end
      end)

      log:debug("[background::callbacks] Registered %d actions for chat event: %s", #event_config.actions, event)
    end
  end
end

return M
