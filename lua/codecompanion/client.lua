local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")

_G.codecompanion_jobs = {}

---@param status string
local function fire_autocmd(status)
  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequest", data = { status = status } })
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
local function close_request(bufnr, opts)
  if bufnr then
    if opts and opts.shutdown then
      _G.codecompanion_jobs[bufnr].handler:shutdown()
    end
    _G.codecompanion_jobs[bufnr] = nil
  end
  fire_autocmd("finished")
end

---@param code integer
---@param stdout string
---@return nil|string
---@return nil|any
local function parse_response(code, stdout)
  if code ~= 0 then
    log:error("Error: %s", stdout)
    return string.format("Error: %s", stdout)
  end

  local ok, data = pcall(vim.json.decode, stdout, { luanil = { object = true } })
  if not ok then
    log:error("Error malformed json: %s", data)
    return string.format("Error malformed json: %s", data)
  end

  if data.error then
    log:error("API Error: %s", data.error.message)
    return string.format("API Error: %s", data.error.message)
  end

  return nil, data
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

  local function handle_error(data)
    log:error("Error: %s", data)
    close_request(bufnr)
    return cb(string.format("There was an error from API: %s: ", data))
  end

  local handler = self.opts.request({
    url = adapter.url,
    timeout = 1000,
    raw = adapter.raw or { "--no-buffer" },
    headers = headers,
    body = body,
    stream = self.opts.schedule(function(_, data)
      log:trace("Chat data: %s", data)
      -- log:trace("----- For Adapter test creation -----\nRequest: %s\n ---------- // END ----------", data)

      if _G.codecompanion_jobs[bufnr] and _G.codecompanion_jobs[bufnr].status == "stopping" then
        close_request(bufnr, { shutdown = true })
        return cb(nil, nil, true)
      end

      if not adapter.callbacks.should_skip(data) then
        if adapter.callbacks.has_error(data) then
          return handle_error(data)
        end

        if data and type(adapter.callbacks.format_data) == "function" then
          data = adapter.callbacks.format_data(data)
        end

        if adapter.callbacks.is_complete(data) then
          log:trace("Chat completed")
          close_request(bufnr)
          return cb(nil, nil, true)
        end

        if data and data ~= "" then
          local ok, json = pcall(self.opts.decode, data, { luanil = { object = true } })

          if not ok then
            close_request(bufnr)
            log:error("Decoding error: %s", json)
            log:error("Data trace: %s", data)
            return cb(string.format("Error decoding data: %s", json))
          end

          cb(nil, json)
        end
      else
        if adapter.callbacks.has_error(data) then
          return handle_error(data)
        end
      end
    end),
    on_error = function(err, _, _)
      log:error("Error: %s", err)
      close_request(bufnr)
    end,
  })

  log:debug("Stream Request: %s", handler.args)
  start_request(bufnr, handler)
end

---Call the API and block until the response is received
---@param adapter CodeCompanion.Adapter
---@param payload table
---@param cb fun(err: nil|string, response: nil|table)
function Client:call(adapter, payload, cb)
  cb = log:wrap_cb(cb, "Response error: %s")

  local cmd = {
    "curl",
    adapter.url,
  }

  if adapter.raw then
    for _, v in ipairs(adapter.raw) do
      table.insert(cmd, v)
    end
  else
    table.insert(cmd, "--no-buffer")
  end

  if adapter.headers then
    for k, v in pairs(adapter.headers) do
      table.insert(cmd, "-H")
      table.insert(cmd, string.format("%s: %s", k, v))
    end
  end

  table.insert(cmd, "-d")
  table.insert(
    cmd,
    vim.json.encode(vim.tbl_extend("keep", adapter.parameters, {
      messages = payload,
    }))
  )
  log:trace("Request payload: %s", cmd)

  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    log:error("Error calling curl: %s", result)
    return cb("Error executing curl", nil)
  else
    local err, data = parse_response(0, result)
    if err then
      return cb(err, nil)
    else
      return cb(nil, data)
    end
  end
end

return Client
