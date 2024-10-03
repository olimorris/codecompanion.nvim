local config = require("codecompanion").config

local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")
local util = require("codecompanion.utils.util")

---@class CodeCompanion.Client
---@field adapter CodeCompanion.Adapter
---@field static table
---@field opts nil|table
---@field user_args nil|table
local Client = {}
Client.static = {}

-- This makes it easier to mock during testing
Client.static.opts = {
  post = { default = curl.post },
  get = { default = curl.get },
  encode = { default = vim.json.encode },
  schedule = { default = vim.schedule_wrap },
}

---@class CodeCompanion.ClientArgs
---@field adapter CodeCompanion.Adapter
---@field opts nil|table
---@field user_args nil|table

---@param args CodeCompanion.ClientArgs
---@return CodeCompanion.Client
function Client.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    opts = args.opts or schema.get_default(Client.static.opts, args.opts),
    user_args = args.user_args or {},
  }, { __index = Client })
end

---@param payload table The payload to be sent to the endpoint
---@param cb fun(err: nil|string, chunk: nil|table) Callback function, executed when the request has finished (can be called multiple times if the request is streaming)
---@param after? fun() Function to run when the request is finished
---@param opts? table Options that can be passed to the request
---@return table|nil The Plenary job
function Client:request(payload, cb, after, opts)
  opts = opts or {}
  cb = log:wrap_cb(cb, "Response error: %s")

  local adapter = self.adapter
  local handlers = adapter.handlers

  if handlers and handlers.setup then
    local ok = handlers.setup(adapter)
    if not ok then
      return
    end
  end

  adapter:get_env_vars()

  local body = self.opts.encode(
    vim.tbl_extend(
      "keep",
      handlers.form_parameters and handlers.form_parameters(adapter, adapter:set_env_vars(adapter.parameters), payload)
        or {},
      handlers.form_messages and handlers.form_messages(adapter, payload) or {},
      handlers.set_body and handlers.set_body(adapter, payload) or {}
    )
  )

  local request_opts = {
    url = adapter:set_env_vars(adapter.url),
    headers = adapter:set_env_vars(adapter.headers),
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    raw = adapter.raw or { "--no-buffer" },
    body = body or "",
    -- This is called when the request is finished. It will only ever be called
    -- once, even if the endpoint is streaming.
    callback = function(data)
      vim.schedule(function()
        if (not adapter.opts.stream) and data and data ~= "" then
          log:trace("Output data:\n%s", data)
          cb(nil, data)
        end
        if after and type(after) == "function" then
          after()
        end
        if handlers and handlers.on_exit then
          handlers.on_exit(adapter, data)
        end
        if handlers and handlers.teardown then
          handlers.teardown(adapter)
        end

        opts["status"] = "success"
        if data.status >= 400 then
          opts["status"] = "error"
        end

        util.fire("RequestFinished", opts)
        if self.user_args.event then
          util.fire("RequestFinished" .. (self.user_args.event or ""), opts)
        end
      end)
    end,
    on_error = function(err, _, code)
      log:error("Error %s: %s", code, err)
      return cb(err, nil)
    end,
  }

  if adapter.opts and adapter.opts.stream then
    -- This will be called multiple times until the stream is finished
    request_opts["stream"] = self.opts.schedule(function(_, data)
      if data and data ~= "" then
        log:trace("Output data:\n%s", data)
      end
      cb(nil, data)
    end)
  end

  local request = "post"
  if adapter.opts and adapter.opts.method then
    request = adapter.opts.method:lower()
  end

  local handler = self.opts[request](request_opts)
  util.fire("RequestStarted", opts)

  if handler and handler.args then
    log:debug("Request:\n%s", handler.args)
  end
  if self.user_args.event then
    util.fire("RequestStarted" .. (self.user_args.event or ""), opts)
  end

  return handler
end

return Client
