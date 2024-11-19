local Curl = require("plenary.curl")
local Path = require("plenary.path")

local config = require("codecompanion.config")
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
  post = { default = Curl.post },
  get = { default = Curl.get },
  encode = { default = vim.json.encode },
  schedule = { default = vim.schedule_wrap },
}

---@class CodeCompanion.ClientArgs
---@field adapter CodeCompanion.Adapter
---@field opts nil|table
---@field user_args nil|table

---@param args CodeCompanion.ClientArgs
---@return table
function Client.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    opts = args.opts or schema.get_default(Client.static.opts, args.opts),
    user_args = args.user_args or {},
  }, { __index = Client })
end

---@class CodeCompanion.Adapter.RequestActions
---@field callback fun(err: nil|string, chunk: nil|table) Callback function, executed when the request has finished or is called multiple times if the request is streaming
---@field done? fun() Function to run when the request is complete

---@param payload table The payload to be sent to the endpoint
---@param actions CodeCompanion.Adapter.RequestActions
---@param opts? table Options that can be passed to the request
---@return table|nil The Plenary job
function Client:request(payload, actions, opts)
  opts = opts or {}
  local cb = log:wrap_cb(actions.callback, "Response error: %s")

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

  local body_file = Path.new(vim.fn.tempname() .. ".json")
  body_file:write(vim.split(body, "\n"), "w")

  log:info("Request body file: %s", body_file.filename)

  local function cleanup(status)
    if vim.tbl_contains({ "DEBUG", "ERROR", "INFO" }, config.opts.log_level) and status ~= "error" then
      body_file:rm()
    end
  end

  local request_opts = {
    url = adapter:set_env_vars(adapter.url),
    headers = adapter:set_env_vars(adapter.headers),
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    raw = adapter.raw or { "--no-buffer" },
    body = body_file.filename or "",
    -- This is called when the request is finished. It will only ever be called
    -- once, even if the endpoint is streaming.
    callback = function(data)
      vim.schedule(function()
        if (not adapter.opts.stream) and data and data ~= "" then
          log:trace("Output data:\n%s", data)
          cb(nil, data)
        end
        if handlers and handlers.on_exit then
          handlers.on_exit(adapter, data)
        end
        if handlers and handlers.teardown then
          handlers.teardown(adapter)
        end
        if actions.done and type(actions.done) == "function" then
          actions.done()
        end

        opts.status = "success"
        if data.status >= 400 then
          opts.status = "error"
        end

        util.fire("RequestFinished", opts)
        cleanup(opts.status)
        if self.user_args.event then
          util.fire("RequestFinished" .. (self.user_args.event or ""), opts)
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        cb(err, nil)
        return util.fire("RequestFinished", opts)
      end)
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

  local job = self.opts[request](request_opts)

  util.fire("RequestStarted", opts)

  if job and job.args then
    log:debug("Request:\n%s", job.args)
  end
  if self.user_args.event then
    util.fire("RequestStarted" .. (self.user_args.event or ""), opts)
  end

  return job
end

return Client
