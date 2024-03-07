local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")

local api = vim.api

_G.codecompanion_jobs = {}

---@param status string
local function fire_autocmd(status)
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequest", data = { status = status } })
end

---@param bufnr? number
---@param handler? table
local function start_request(bufnr, handler)
  if bufnr and handler then
    _G.codecompanion_jobs[bufnr] = {
      status = "running",
      handler = handler,
    }
  end
  fire_autocmd("started")
end

---@param bufnr? number
---@param opts? table
local function stop_request(bufnr, opts)
  if bufnr then
    if opts and opts.shutdown then
      _G.codecompanion_jobs[bufnr].handler:shutdown()
    end
    _G.codecompanion_jobs[bufnr] = nil
  end
  fire_autocmd("finished")
end

---@class CodeCompanion.Client
---@field static table
---@field secret_key string
---@field organization nil|string
---@field opts nil|table
local Client = {}
Client.static = {}

Client.static.opts = {
  request = { default = curl.post },
  encode = { default = vim.json.encode },
  decode = { default = vim.json.decode },
  schedule = { default = vim.schedule_wrap },
}

---@class CodeCompanion.ClientArgs
---@field secret_key string
---@field organization nil|string
---@field opts nil|table

---@param args? CodeCompanion.ClientArgs
---@return CodeCompanion.Client
function Client.new(args)
  args = args or {}

  return setmetatable({
    opts = args.opts or schema.get_default(Client.static.opts, args.opts),
  }, { __index = Client })
end

---@param adapter CodeCompanion.Adapter
---@param payload table the messages to send to the API
---@param bufnr number
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@return nil
function Client:stream(adapter, payload, bufnr, cb)
  cb = log:wrap_cb(cb, "Response error: %s")

  --TODO: Check for any errors env variables
  local headers = adapter:replace_header_vars().headers
  local body =
    self.opts.encode(vim.tbl_extend("keep", adapter.parameters or {}, adapter.callbacks.form_messages(payload)))

  log:debug("Adapter: %s", { adapter.name, adapter.url, adapter.raw, headers, body })

  local stop_request_cmd = api.nvim_create_autocmd("User", {
    desc = "Stop the current request",
    pattern = "CodeCompanionRequest",
    callback = function(request)
      if request.data.buf ~= bufnr or request.data.action ~= "stop_request" then
        return
      end

      return stop_request(bufnr, { shutdown = true })
    end,
  })

  local handler = self.opts.request({
    url = adapter.url,
    timeout = 1000,
    raw = adapter.raw or { "--no-buffer" },
    headers = headers,
    body = body,
    stream = self.opts.schedule(function(_, data)
      log:trace("Chat data: %s", data)
      log:trace("----- For Adapter test creation -----\nRequest: %s\n ---------- // END ----------", data)

      if _G.codecompanion_jobs[bufnr] and _G.codecompanion_jobs[bufnr].status == "stopping" then
        stop_request(bufnr, { shutdown = true })
        return cb(nil, nil, true)
      end

      if adapter.callbacks.is_complete(data) then
        log:trace("Chat completed")
        stop_request(bufnr)
        api.nvim_del_autocmd(stop_request_cmd)
        return cb(nil, nil, true)
      end

      cb(nil, data)
    end),
    on_error = function(err, _, _)
      log:error("Error: %s", err)
      stop_request(bufnr)
      api.nvim_del_autocmd(stop_request_cmd)
    end,
  })

  log:debug("Stream Request: %s", handler.args)
  start_request(bufnr, handler)
end

return Client
