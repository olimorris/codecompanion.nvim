local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")

local api = vim.api

---@param status string
local function announce(status)
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequest", data = { status = status } })
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
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@param after_fn? fun() Will be called after the request is finished
---@return table The Plenary job
function Client:stream(adapter, payload, cb, after_fn)
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

  local handler = self.opts
    .request({
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
          return cb(nil, nil, true)
        end

        cb(nil, data)
      end),
      on_error = function(err, _, code)
        if code then
          log:error("Error: %s", err)
        end
        return cb(nil, nil, true)
      end,
    })
    :after(function()
      vim.schedule(function()
        announce("finished")
      end)
      if after_fn and type(after_fn) == "function" then
        after_fn()
      end
    end)

  if handler and handler.args then
    log:debug("Stream Request: %s", handler.args)
  end
  announce("started")

  return handler
end

return Client
