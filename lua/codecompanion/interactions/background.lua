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

  if not self.adapter then
    log:error("No adapter found for Background strategy")
    -- We should return or handle this error appropriately.
    -- For now, let's let it proceed but it will fail later.
  end

  if self.adapter.type == "http" then
    self.settings = schema.get_default(self.adapter, args.settings)
  end

  return self
end

---Add a message to the stack.
---@param message { role: string, content: string }
---@return CodeCompanion.Background
function Background:add_message(message)
  table.insert(self.messages, message)
  return self
end

---Submit the request synchronously.
---@param opts? { silent?: boolean }
---@return table|nil, table|nil -- response, error
function Background:submit_sync(opts)
  if self.adapter.type ~= "http" then
    return nil, { message = "submit_sync only supports HTTP adapters" }
  end

  local client = http.new({ adapter = self.adapter })
  local payload = {
    messages = self.adapter:map_roles(vim.deepcopy(self.messages)),
  }

  log:trace("Background Sync Payload:\n%s", payload)
  local response, err = client:send_sync(payload, opts)

  if err then
    log:error("Background sync request failed: %s", err.stderr or err.message)
    return nil, err
  end

  local result = self.adapter.handlers.chat_output(self.adapter, response)
  return result, nil
end

---Submit the request asynchronously.
---@param submit_opts { on_chunk?: function, on_done?: function, on_error?: function, silent?: boolean }
---@return CodeCompanion.HTTPClient.RequestHandle
function Background:submit_async(submit_opts)
  if self.adapter.type ~= "http" then
    if submit_opts.on_error then
      submit_opts.on_error({ message = "submit_async only supports HTTP adapters" })
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

return Background
