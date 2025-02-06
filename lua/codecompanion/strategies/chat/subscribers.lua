--[[
Subscribers are functions that are set from outside the chat buffer that can be
executed at the end of every response. This is used in workflows, allowing
for consecutive prompts to be sent and even automatically submitted.
]]
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Subscribers
local Subscribers = {}

---@param args CodeCompanion.SubscribersArgs
function Subscribers.new(args)
  return setmetatable({
    queue = {},
    stopped = false,
  }, { __index = Subscribers })
end

---Link a subscriber to the chat buffer
---@param event CodeCompanion.Chat.Event
---@return nil
function Subscribers:subscribe(event)
  event.id = math.random(10000000)
  table.insert(self.queue, event)
end

---Unsubscribe an object from a chat buffer
---@param event CodeCompanion.Chat.Event
---@return nil
function Subscribers:unsubscribe(event)
  local name = event.data and event.data.name or ""

  for i, subscriber in ipairs(self.queue) do
    if subscriber.id == event.id then
      log:debug("[Subscription] Unsubscribing %s (%s)", name, event.id)
      table.remove(self.queue, i)
    end
  end
end

---Does the chat buffer have any subscribers?
---@return boolean
function Subscribers:has_subscribers()
  return #self.queue > 0
end

---Execute the subscriber's callback
---@param chat CodeCompanion.Chat
---@param event CodeCompanion.Chat.Event
---@return nil
function Subscribers:action(chat, event)
  local name = event.data and event.data.name or ""

  if type(event.reuse) == "function" then
    local reuse = event.reuse(chat)
    if reuse then
      log:debug("[Subscription] Reusing %s (%s)", name, event.id)
      return event.callback(chat)
    end
    return self:unsubscribe(event)
  end

  log:debug("[Subscription] Actioning: %s (%s)", name, event.id)
  event.callback(chat)
  if event.data and event.data.type == "once" then
    return self:unsubscribe(event)
  end
end

---Process the next subscriber in the queue
---@param chat CodeCompanion.Chat
---@return nil
function Subscribers:process(chat)
  if not self:has_subscribers() then
    return
  end

  vim.iter(self.queue):each(function(subscriber)
    if not subscriber.order or subscriber.order < chat.cycle then
      self:action(chat, subscriber)
      self:submit(chat, subscriber)
    end
  end)
end

---Automatically submit the chat buffer
---@param chat CodeCompanion.Chat
---@param subscriber CodeCompanion.Chat.Event
function Subscribers:submit(chat, subscriber)
  if subscriber.data and subscriber.data.opts and subscriber.data.opts.auto_submit and not self.stopped then
    -- Defer the call to prevent rate limit bans
    vim.defer_fn(function()
      chat:submit()
    end, config.opts.submit_delay)
  end
end

---When a request has been stopped, we should stop any automatic subscribers
---@return CodeCompanion.Subscribers
function Subscribers:stop()
  log:debug("[Subscription] Stopping")
  self.stopped = true
  return self
end

return Subscribers
