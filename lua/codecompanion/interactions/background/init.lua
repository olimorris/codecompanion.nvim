local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")
local http = require("codecompanion.http")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")

---@class CodeCompanion.Background
---@field adapter CodeCompanion.HTTPAdapter The adapter to use for the background task
---@field id number The unique identifier for the background task
---@field messages CodeCompanion.Chat.Messages The messages for the background task
---@field settings table The settings used in the adapter
local Background = {}

---@class CodeCompanion.Background.Args
---@field adapter? CodeCompanion.HTTPAdapter|string The adapter to use
---@field messages? CodeCompanion.Chat.Messages The messages to initialize with
---@field settings? table The settings for the adapter

---@param args CodeCompanion.Background.Args
---@return CodeCompanion.Background
function Background.new(args)
  args = args or {}

  local self = setmetatable({
    id = math.random(10000000),
    messages = args.messages or {},
  }, { __index = Background })

  if args.adapter and adapters.resolved(args.adapter) then
    self.adapter = args.adapter
  else
    self.adapter = adapters.resolve(args.adapter or config.strategies.chat.adapter)
  end

  if self.adapter.type ~= "http" then
    return log:error("[Background] Only HTTP adapters are supported for background interactions")
  end
  if not self.adapter then
    return log:error("[Background] No adapter assigned for background interactions")
  end

  self.settings = schema.get_default(self.adapter, args.settings)

  return self ---@type CodeCompanion.Background
end

---Submit the request synchronously.
---@param opts? { silent?: boolean }
---@return table|nil, table|nil -- response, error
function Background:submit_sync(opts)
  if self.adapter.type ~= "http" then
    return nil, { message = "[Background] submit_sync only supports HTTP adapters" }
  end

  local client = http.new({ adapter = self.adapter })
  local payload = {
    messages = self.adapter:map_roles(vim.deepcopy(self.messages)),
  }

  log:debug("[Background] Background Sync Payload:\n%s", payload)
  local response, err = client:send_sync(payload, opts)

  if err then
    log:error("[Background] sync request failed: %s", err.stderr or err.message)
    return nil, err
  end

  local result = adapters.call_handler(self.adapter, "parse_chat", response)
  return result, nil
end

---Submit the request asynchronously.
---@param submit_opts { on_chunk?: function, on_done?: function, on_error?: function, silent?: boolean }
---@return CodeCompanion.HTTPClient.RequestHandle
function Background:submit_async(submit_opts)
  if self.adapter.type ~= "http" then
    if submit_opts.on_error then
      submit_opts.on_error({ message = "[Background] submit_async only supports HTTP adapters" })
    end
    -- Returning a dummy handle
    return {
      id = "",
      job = nil,
      cancel = function() end,
      status = function()
        return "error"
      end,
    }
  end

  local client = http.new({ adapter = self.adapter })
  local payload = {
    messages = self.adapter:map_roles(vim.deepcopy(self.messages)),
  }

  log:trace("Background Async Payload:\n%s", payload)
  return client:send(payload, submit_opts)
end

---Ask the LLM synchronously with provided messages
---@param messages CodeCompanion.Chat.Messages
---@param opts? { silent?: boolean }
---@return any, table|nil -- parsed response, error
function Background:ask_sync(messages, opts)
  opts = opts or {}

  if self.adapter.type ~= "http" then
    return nil, { message = "[Background] ask_sync only supports HTTP adapters" }
  end

  local client = http.new({ adapter = self.adapter })
  local payload = {
    messages = self.adapter:map_roles(vim.deepcopy(messages)),
  }

  log:debug("[Background] Ask Sync Payload:\n%s", payload)
  local response, err = client:send_sync(payload, { silent = opts.silent })

  if err then
    log:error("[Background] ask_sync failed: %s", err.stderr or err.message)
    return nil, err
  end

  local result = adapters.call_handler(self.adapter, "parse_chat", response)
  return result, nil
end

---Ask the LLM asynchronously with provided messages
---@param messages CodeCompanion.Chat.Messages
---@param opts { on_done: function, on_error?: function, on_chunk?: function, silent?: boolean }
---@return CodeCompanion.HTTPClient.RequestHandle
function Background:ask_async(messages, opts)
  assert(opts.on_done, "on_done callback is required for ask_async")

  if self.adapter.type ~= "http" then
    if opts.on_error then
      opts.on_error({ message = "[Background] ask_async only supports HTTP adapters" })
    end
    -- Returning a dummy handle
    return {
      id = "",
      job = nil,
      cancel = function() end,
      status = function()
        return "error"
      end,
    }
  end

  local client = http.new({ adapter = self.adapter })
  local payload = {
    messages = self.adapter:map_roles(vim.deepcopy(messages)),
  }

  log:trace("[Background] Ask Async Payload:\n%s", payload)
  return client:send(payload, opts)
end

return Background
