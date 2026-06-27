local Curl = require("plenary.curl")

local adapter_utils = require("codecompanion.adapters.utils")
local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

---@class CodeCompanion.HTTPClient
---@field adapter CodeCompanion.HTTPAdapter
---@field methods table
---@field opts nil|table
---@field static table
---@field user_args nil|table
local Client = {}
Client.static = {}

-- Define our static methods for the HTTP client making it easier to mock and test
Client.static.methods = {
  post = { default = Curl.post },
  get = { default = Curl.get },
  encode = { default = vim.json.encode },
  schedule = { default = vim.schedule },
  schedule_wrap = { default = vim.schedule_wrap },
}

---@param headers table
---@return string
local function write_headers_file(headers)
  local lines = {}
  for k, v in pairs(headers) do
    table.insert(lines, k .. ": " .. tostring(v))
  end

  local path = vim.fn.tempname() .. ".headers"
  files.write_to_path(path, table.concat(lines, "\n"))

  return path
end

---@param paths { body: string, headers: string }
---@param status? string
---@return nil
local function delete_temp_files(paths, status)
  -- Don't remove any files if there was an error, so the user can debug
  if status == "error" then
    return
  end

  if vim.tbl_contains({ "ERROR", "INFO" }, config.opts.log_level) then
    files.delete(paths.body)
    files.delete(paths.headers)
  end
end

---Allow for easier testing/mocking of the static methods
---@param opts? table
---@return table
local function transform_static_methods(opts)
  local ret = {}
  for k, v in pairs(Client.static.methods) do
    if opts and opts[k] ~= nil then
      ret[k] = opts[k]
    else
      ret[k] = v.default
    end
  end
  return ret
end

---@param self CodeCompanion.HTTPClient
---@return CodeCompanion.HTTPAdapter|nil
local function prepare_adapter(self)
  local adapter = vim.deepcopy(self.adapter)
  if adapters.call_handler(adapter, "setup") == false then
    return nil
  end

  return adapter_utils.get_env_vars(adapter, { timeout = config.adapters.opts.cmd_timeout })
end

---Encode the JSON request body from the adapter's build handlers
---@param self CodeCompanion.HTTPClient
---@param adapter CodeCompanion.HTTPAdapter
---@param payload { messages: table, tools?: table }
---@return string
local function encode_body(self, adapter, payload)
  return self.methods.encode(
    vim.tbl_extend(
      "keep",
      adapters.call_handler(
        adapter,
        "build_parameters",
        adapter_utils.set_env_vars(adapter, adapter.parameters),
        payload.messages
      ) or {},
      adapters.call_handler(adapter, "build_messages", payload.messages) or {},
      adapters.call_handler(adapter, "build_tools", payload.tools) or {},
      adapter.body and adapter.body or {},
      adapters.call_handler(adapter, "build_body", payload) or {}
    )
  )
end

---@return table
local function curl_args()
  return {
    "--retry",
    "3",
    "--retry-delay",
    "1",
    "--keepalive-time",
    "60",
    "--connect-timeout",
    "10",
  }
end

---@param adapter CodeCompanion.HTTPAdapter
---@return string
local function resolve_method(adapter)
  if adapter.opts and adapter.opts.method then
    return adapter.opts.method:lower()
  end

  return "post"
end

---Adapter metadata fired with request events
---@param adapter CodeCompanion.HTTPAdapter
---@return table
local function adapter_event_data(adapter)
  local model = adapter.schema.model.default

  return {
    name = adapter.name,
    formatted_name = adapter.formatted_name,
    model = (type(model) == "function" and model(adapter)) or model or "",
  }
end

---@class CodeCompanion.HTTPClientArgs
---@field adapter CodeCompanion.HTTPAdapter
---@field opts? nil|table
---@field user_args nil|table

---@param args CodeCompanion.HTTPClientArgs
---@return table
function Client.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    methods = transform_static_methods(args.opts),
    opts = args.opts or {},
    user_args = args.user_args or {},
  }, { __index = Client })
end

---@class CodeCompanion.HTTPClient.Request
---@field id string
---@field adapter? CodeCompanion.HTTPAdapter

---@class CodeCompanion.HTTPClient.RequestHandle
---@field id string
---@field job table|nil
---@field cancel fun(): boolean
---@field status fun(): "pending"|"streaming"|"success"|"error"|"cancelled"

---Send a payload and receive the response over time via callbacks, returning a cancelable handle
---@param payload { messages: table, tools?: table }
---@param opts { stream?: boolean,
---             on_chunk?: fun(chunk: table, meta: CodeCompanion.HTTPClient.Request),
---             on_done?: fun(response: table|nil, meta: CodeCompanion.HTTPClient.Request),
---             on_error?: fun(err: table, meta: CodeCompanion.HTTPClient.Request),
---             silent?: boolean,
---             timeout?: number}|nil
---@return CodeCompanion.HTTPClient.RequestHandle
function Client:stream(payload, opts)
  opts = opts or {}
  local handle_state = "pending"
  local meta = { id = tostring(math.random(10000000)) }
  local had_error = false

  ---@param s "pending"|"streaming"|"success"|"error"|"cancelled"
  local function set_state(s)
    handle_state = s
  end

  local request_opts = vim.tbl_extend("force", opts or {}, { id = meta.id })

  local job = self:_dispatch(payload, {
    callback = function(err, data, adapter)
      if adapter then
        meta.adapter = adapter
      end
      if err then
        had_error = true
        set_state("error")
        if opts.on_error then
          opts.on_error(err, meta)
        end
        return
      end

      local is_streaming = self.adapter and self.adapter.opts and self.adapter.opts.stream

      if is_streaming then
        if data and data ~= "" then
          set_state("streaming")
          if opts.on_chunk then
            opts.on_chunk(data, meta)
          end
        end
        return
      end

      -- Non-streaming final response table
      if type(data) == "table" and data.status then
        if data.status >= 400 then
          return
        end
        set_state("success")
        if opts.on_done then
          opts.on_done(data, meta)
        end
      end
    end,

    -- Defer on_done to the next tick to suppress it if an error arrives later on
    done = function()
      local is_streaming = self.adapter and self.adapter.opts and self.adapter.opts.stream
      if not is_streaming then
        return
      end
      self.methods.schedule(function()
        if not had_error then
          set_state("success")
          if opts.on_done then
            opts.on_done(nil, meta)
          end
        end
      end)
    end,
  }, request_opts)

  local handle = {
    id = meta.id,
    job = job,
    cancel = function()
      if job and job.shutdown then
        pcall(function()
          job:shutdown()
        end)
        set_state("cancelled")
        return true
      end
      return false
    end,
    status = function()
      return handle_state
    end,
  }

  return handle
end

---Send a payload and block until the single response returns
---@param payload { messages: table, tools?: table }
---@param opts { stream?: false, timeout?: number, silent?: boolean }|nil
---@return table|nil, table|nil  -- response, err
function Client:fetch(payload, opts)
  opts = opts or {}

  local adapter = prepare_adapter(self)
  if not adapter then
    return nil, { message = "Failed to setup adapter", stderr = "setup=false" }
  end

  local body = encode_body(self, adapter, payload)

  local body_file = vim.fn.tempname() .. ".json"
  files.write_to_path(body_file, body)

  local raw = curl_args()

  if adapter.raw then
    vim.list_extend(raw, adapter_utils.set_env_vars(adapter, adapter.raw))
  end

  local headers_file = write_headers_file(adapter_utils.set_env_vars(adapter, adapter.headers))
  vim.list_extend(raw, { "--header", "@" .. headers_file })

  local request_opts = {
    body = body_file or "",
    insecure = config.adapters.http.opts.allow_insecure,
    proxy = config.adapters.http.opts.proxy,
    raw = raw,
    timeout = opts.timeout,
    url = adapter_utils.set_env_vars(adapter, adapter.url),
  }

  local method = resolve_method(adapter)

  local event_opts = {
    adapter = adapter_event_data(adapter),
    id = tostring(math.random(10000000)),
  }
  if not opts.silent then
    utils.fire("RequestStarted", event_opts)
  end

  local response, err = nil, nil
  local ok, result = pcall(self.methods[method], request_opts)
  if not ok then
    err = { message = tostring(result), stderr = tostring(result) }
  else
    response = result
    if response and response.status and response.status >= 400 then
      err = { message = string.format([[%d error: ]], response.status), stderr = response, status = response.status }
      response = nil
    end
  end

  adapters.call_handler(adapter, "on_exit", response or (err and err.stderr))
  adapters.call_handler(adapter, "teardown")

  if not opts.silent then
    utils.fire("RequestFinished", event_opts)
  end

  delete_temp_files({ body = body_file, headers = headers_file })
  return response, err
end

---@class CodeCompanion.HTTPAdapter.RequestActions
---@field callback fun(err: nil|table, chunk: nil|table, adapter?: CodeCompanion.HTTPAdapter) Callback function, executed when the request has finished or is called multiple times if the request is streaming
---@field done? fun() Function to run when the request is complete

---Build the request, initiate curl and stream
---@param payload { messages: table, tools: table|nil }
---@param actions CodeCompanion.HTTPAdapter.RequestActions
---@param opts? table
---@return table|nil The Plenary job
function Client:_dispatch(payload, actions, opts)
  -- Check if the adapter has a custom request function and use it instead
  if
    self.adapter
    and self.adapter.opts
    and self.adapter.opts.request
    and type(self.adapter.opts.request) == "function"
  then
    return self.adapter.opts.request(self, payload, actions, opts)
  end

  opts = opts or {}
  local cb = log:wrap_cb(actions.callback, "Response error: %s") --[[@type function]]

  local adapter = prepare_adapter(self)
  if not adapter then
    return log:error("Failed to setup adapter")
  end

  local body = encode_body(self, adapter, payload)

  local body_file = vim.fn.tempname() .. ".json"
  files.write_to_path(body_file, body)

  log:info("Request body file: %s", body_file)

  local raw = curl_args()

  if adapter.opts and adapter.opts.stream then
    table.insert(raw, "--tcp-nodelay")
    table.insert(raw, "--no-buffer")
  end

  if adapter.raw then
    vim.list_extend(raw, adapter_utils.set_env_vars(adapter, adapter.raw))
  end

  local headers_file = write_headers_file(adapter_utils.set_env_vars(adapter, adapter.headers))
  vim.list_extend(raw, { "--header", "@" .. headers_file })

  -- Capture streaming errors for use in final callback
  local stream_error_body = nil

  local request_opts = {
    url = adapter_utils.set_env_vars(adapter, adapter.url),
    insecure = config.adapters.http.opts.allow_insecure,
    proxy = config.adapters.http.opts.proxy,
    raw = raw,
    body = body_file or "",
    -- Final callback invoked when HTTP request is complete
    callback = function(data)
      self.methods.schedule(function()
        if (not adapter.opts.stream) and data and data ~= "" then
          log:debug("Output data:\n%s", data)
          cb(nil, data, adapter)
        end

        adapters.call_handler(adapter, "on_exit", data)
        adapters.call_handler(adapter, "teardown")

        if actions.done and type(actions.done) == "function" then
          actions.done()
        end

        opts.status = "success"
        if data and data.status and data.status >= 400 then
          opts.status = "error"
          actions.callback({ message = string.format([[%d error: ]], data.status), stderr = data }, nil)
        elseif not data and stream_error_body then
          opts.status = "error"
          actions.callback({ message = "Request failed", stderr = stream_error_body }, nil)
        end

        if not opts.silent then
          utils.fire("RequestFinished", opts)
        end
        delete_temp_files({ body = body_file, headers = headers_file }, opts.status)
        if self.user_args.event then
          if not opts.silent then
            utils.fire(self.user_args.event, opts)
          end
        end
      end)
    end,
    on_error = function(err)
      self.methods.schedule(function()
        actions.callback(err, nil)
        if not opts.silent then
          utils.fire("RequestFinished", opts)
        end
      end)
    end,
  }

  if adapter.opts and adapter.opts.stream then
    local has_started_steaming = false

    -- Turn off plenary's default compression
    request_opts["compressed"] = adapter.opts.compress or false

    -- This will be called multiple times until the stream is finished
    request_opts["stream"] = self.methods.schedule_wrap(function(_, data)
      if data and data ~= "" then
        log:debug("Output data:\n%s", data)
        if data:match('^%s*{"error"') or data:match('^%s*{"type"%s*:%s*"error"') then
          stream_error_body = data
          return -- Don't pass error to cb, handle in final callback
        end
      end
      if not has_started_steaming then
        has_started_steaming = true
        if not opts.silent then
          utils.fire("RequestStreaming", opts)
        end
      end
      cb(nil, data, adapter)
    end)
  end

  local job = self.methods[resolve_method(adapter)](request_opts)

  opts.id = opts.id or math.random(10000000)
  opts.adapter = adapter_event_data(adapter)

  if not opts.silent then
    utils.fire("RequestStarted", opts)
  end

  if job and job.args then
    log:debug("Request:\n%s", job.args)
  end
  if self.user_args.event then
    if not opts.silent then
      utils.fire(self.user_args.event, opts)
    end
  end

  job.cancel = function()
    job:shutdown()
  end

  return job
end

return Client
