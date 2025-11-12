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
    self.adapter = args.adapter --[[@as CodeCompanion.HTTPAdapter]]
  else
    self.adapter = adapters.resolve(args.adapter or config.strategies.chat.adapter)
  end

  -- Silence errors
  if self.adapter.type ~= "http" then
    return log:debug("[background::init] Only HTTP adapters are supported for background interactions")
  end
  if not self.adapter then
    return log:debug("[background::init] No adapter assigned for background interactions")
  end

  self.settings = schema.get_default(self.adapter, args.settings)
  self.adapter:map_schema_to_params(self.settings)

  return self ---@type CodeCompanion.Background
end

---Ask the LLM synchronously with provided messages
---@param background CodeCompanion.Background
---@param messages CodeCompanion.Chat.Messages
---@param opts? { silent?: boolean, parse_handler?: string }
---@return any, table|nil -- parsed response, error
local function ask_sync(background, messages, opts)
  opts = opts or {}

  if background.adapter.type ~= "http" then
    return nil, { message = "[background::init] ask_sync only supports HTTP adapters" }
  end

  local client = http.new({ adapter = background.adapter })
  local payload = {
    messages = background.adapter:map_roles(vim.deepcopy(messages)),
  }

  log:debug("[background::init] Ask Sync Payload:\n%s", payload)
  local response, err = client:send_sync(payload, { silent = opts.silent })

  if err then
    log:debug("[background::init] ask_sync failed: %s", err.stderr or err.message)
    return nil, err
  end

  local parse_handler = opts.parse_handler or "parse_chat"
  local result = adapters.call_handler(background.adapter, parse_handler, response.body)
  return result, nil
end

---Ask the LLM asynchronously with provided messages
---@param background CodeCompanion.Background
---@param messages CodeCompanion.Chat.Messages
---@param opts { on_done: function, on_error?: function, on_chunk?: function, silent?: boolean, parse_handler?: string }
---@return CodeCompanion.HTTPClient.RequestHandle
local function ask_async(background, messages, opts)
  assert(opts.on_done, "on_done callback is required for ask_async")

  -- Temporarily disable streaming for this request
  local adapter = vim.deepcopy(background.adapter)
  if adapter.opts then
    adapter.opts.stream = false
  end

  local client = http.new({ adapter = adapter })
  local payload = {
    messages = adapter:map_roles(vim.deepcopy(messages)),
  }

  -- Wrap the on_done callback to parse the response
  local parse_handler = opts.parse_handler or "parse_chat"
  local original_on_done = opts.on_done
  opts.on_done = function(response, meta)
    if not response or not response.body then
      original_on_done(nil, meta)
      return
    end

    local result = adapters.call_handler(adapter, parse_handler, response.body)
    original_on_done(result, meta)
  end

  log:trace("[background::init] Ask Async Payload:\n%s", payload)
  return client:send(payload, opts)
end

---Ask the LLM for a specific response
---@param messages CodeCompanion.Chat.Message[]
---@param opts? { method?: string, silent?: boolean, parse_handler?: string }
function Background:ask(messages, opts)
  opts = vim.tbl_deep_extend("force", { method = "async" }, opts or {})

  if opts.method == "sync" then
    return ask_sync(self, messages, opts)
  end
  return ask_async(self, messages, opts)
end

return Background
