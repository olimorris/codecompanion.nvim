--[[
  A mock HTTP client for testing purposes.
  Drop-in replacement for lua/codecompanion/http.lua.

  Features:
  - Captures all requests (sync and async) for verification
  - Queues responses to return on subsequent calls
  - Simulates async behaviour with vim.schedule
  - Returns request handles with cancel/status methods

  Usage:
  - Via the helper methods in tests/helpers.lua
--]]

local MockHTTPClient = {} --[[@class CodeCompanion.MockHTTPClient]]

---@class CodeCompanion.MockHTTPClient
---@field adapter table
---@field requests table Captured requests
---@field response_queue table Queue of responses to return
---@field methods table

function MockHTTPClient.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    requests = {},
    response_queue = {},
    methods = {
      post = function() end,
      get = function() end,
      encode = vim.json.encode,
      schedule = function(fn)
        fn()
      end,
      schedule_wrap = function(fn)
        return fn
      end,
    },
  }, { __index = MockHTTPClient })
end

---Queue a response to be returned on the next send/send_sync call
---@param response table The mock response
---@return nil
function MockHTTPClient:queue_response(response)
  table.insert(self.response_queue, response)
end

---Get the next queued response
---@return table|nil
function MockHTTPClient:dequeue_response()
  return table.remove(self.response_queue, 1)
end

---Async request - captures request and returns handle with queued response
---@param payload table
---@param opts table
---@return CodeCompanion.HTTPClient.RequestHandle
function MockHTTPClient:send(payload, opts)
  opts = opts or {}
  table.insert(self.requests, { type = "async", payload = payload, opts = opts })

  local response = self:dequeue_response()
  local handle_state = "pending"

  vim.schedule(function()
    if response then
      if opts.on_chunk and response.stream then
        for _, chunk in ipairs(response.stream) do
          opts.on_chunk(chunk, { id = "mock" })
        end
      end
      handle_state = "success"
      if opts.on_done then
        opts.on_done(response, { id = "mock" })
      end
    else
      handle_state = "error"
      if opts.on_error then
        opts.on_error({ message = "No queued response" }, { id = "mock" })
      end
    end
  end)

  return {
    id = "mock_" .. tostring(math.random(10000000)),
    job = nil,
    cancel = function()
      handle_state = "cancelled"
      return true
    end,
    status = function()
      return handle_state
    end,
  }
end

---Sync request - captures request and returns queued response
---@param payload table
---@param opts table
---@return table|nil, table|nil
function MockHTTPClient:send_sync(payload, opts)
  opts = opts or {}
  table.insert(self.requests, { type = "sync", payload = payload, opts = opts })

  local response = self:dequeue_response()

  if response then
    return response, nil
  end

  return nil, { message = "No queued response" }
end

---Get all captured requests
---@return table
function MockHTTPClient:get_requests()
  return self.requests
end

---Get the last captured request
---@return table|nil
function MockHTTPClient:get_last_request()
  return self.requests[#self.requests]
end

---Clear all captured requests
---@return nil
function MockHTTPClient:clear_requests()
  self.requests = {}
end

return MockHTTPClient
