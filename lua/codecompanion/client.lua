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
      if
        _G.codecompanion_jobs[bufnr]
        and _G.codecompanion_jobs[bufnr].handler
        and type(_G.codecompanion_jobs[bufnr].handler.shutdown) == "function"
      then
        _G.codecompanion_jobs[bufnr].handler:shutdown()
      end
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
---@param payload table the payload to send to the API
---@param bufnr number
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@return nil
function Client:stream(adapter, payload, bufnr, cb)
  cb = log:wrap_cb(cb, "Response error: %s")

  --TODO: Check for any errors env variables
  local headers = adapter:replace_header_vars().headers
  local body = self.opts.encode(
    vim.tbl_extend(
      "keep",
      adapter.callbacks.form_parameters(adapter.parameters, payload) or {},
      adapter.callbacks.form_messages(payload)
    )
  )

  local cancel_request = api.nvim_create_autocmd("User", {
    desc = "Stop the current request",
    pattern = "CodeCompanionRequest",
    callback = function(request)
      if request.data.bufnr ~= bufnr or request.data.action ~= "cancel_request" then
        return
      end

      return stop_request(request.data.bufnr, { shutdown = true })
    end,
  })

  local handler = self.opts.request({
    url = adapter.url,
    raw = adapter.raw or { "--no-buffer" },
    headers = headers,
    body = body,
    stream = self.opts.schedule(function(_, data)
      if data then
        log:trace("Chat data: %s", data)
      end
      -- log:trace("----- For Adapter test creation -----\nRequest: %s\n ---------- // END ----------", data)

      if adapter.callbacks.is_complete(data) then
        log:trace("Chat completed")
        stop_request(bufnr)
        api.nvim_del_autocmd(cancel_request)
        return cb(nil, nil, true)
      end

      cb(nil, data)
    end),
    on_error = function(err, _, code)
      if code then
        log:error("Error: %s", err)
      end
      stop_request(bufnr)
      api.nvim_del_autocmd(cancel_request)
      return cb(nil, nil, true)
    end,
  })

  log:debug("Stream Request: %s", handler.args)
  start_request(bufnr, handler)
end

return Client
