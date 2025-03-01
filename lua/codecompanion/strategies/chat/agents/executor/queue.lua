-- Simple Queue implementation
-- Based on deque by Pierre 'catwell' Chapuis
-- Ref: https://github.com/catwell/cw-lua/blob/master/deque/deque.lua

---Add an item to the back of the queue
---@param self table
---@param x any
---@return nil
local push = function(self, x)
  assert(x ~= nil)
  self.tail = self.tail + 1
  self[self.tail] = x
end

---Remove and return an item from the front of the queue
---@param self table
---@return any|nil The removed item or nil if queue is empty
local pop = function(self)
  if self:is_empty() then
    return nil
  end
  local r = self[self.head + 1]
  self.head = self.head + 1
  local r = self[self.head]
  self[self.head] = nil
  return r
end

---Get the number of items in the queue
---@param self table
---@return number Number of items in the queue
local count = function(self)
  return self.tail - self.head
end

---Check if the queue is empty
---@param self table
---@return boolean
local is_empty = function(self)
  return self:count() == 0
end

---Get all items in the queue as a table
---@param self table
---@return table All queue items in order
local contents = function(self)
  local r = {}
  for i = self.head + 1, self.tail do
    r[i - self.head] = self[i]
  end
  return r
end

local methods = {
  push = push,
  pop = pop,
  count = count,
  is_empty = is_empty,
  contents = contents,
}

---Create a new queue
---@return table A new empty queue instance
local new = function()
  local r = { head = 0, tail = 0 }
  return setmetatable(r, { __index = methods })
end

---@class CodeCompanion.Agent.Executor.Queue
---@field head number Internal head pointer
---@field tail number Internal tail pointer
---@field push fun(self: CodeCompanion.Agent.Executor.Queue, x: any): nil Add an item to the back of the queue
---@field pop fun(self: CodeCompanion.Agent.Executor.Queue): any|nil Remove and return an item from the front of the queue
---@field count fun(self: CodeCompanion.Agent.Executor.Queue): number Get the number of items in the queue
---@field is_empty fun(self: CodeCompanion.Agent.Executor.Queue): boolean Check if the queue is empty
---@field contents fun(self: CodeCompanion.Agent.Executor.Queue): table Get all items in the queue as a table

return {
  new = new,
}
