--[[
Subscribers are functions that are set from outside the chat buffer that can be
executed at the end of every response. This is used in workflows, allowing
for consecutive prompts to be sent and even automatically submitted.
]]

---@class CodeCompanion.Subscribers
local Subscribers = {}

---@param args CodeCompanion.SubscribersArgs
function Subscribers.new(args)
  return setmetatable({
    queue = {},
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
---@param id integer|string
---@return nil
function Subscribers:unsubscribe(id)
  for i, subscriber in ipairs(self.queue) do
    if subscriber.id == id then
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
---@param subscriber CodeCompanion.Chat.Event
---@return nil
function Subscribers:action(chat, subscriber)
  subscriber.callback(chat)
  if subscriber.type == "once" then
    self:unsubscribe(subscriber.id)
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
    if subscriber.order and subscriber.order < chat.cycle then
      self:action(chat, subscriber)
    elseif not subscriber.order then
      self:action(chat, subscriber)
    end
  end)
end

return Subscribers
