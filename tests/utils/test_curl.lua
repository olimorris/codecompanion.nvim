local h = require("tests.helpers")

local new_set = MiniTest.new_set

local T = new_set()

local curl, server, base_url

---@param client uv.uv_tcp_t
---@param opts { status: string, headers?: string[], body?: string }
local function respond(client, opts)
  local head = { "HTTP/1.1 " .. opts.status, "Connection: close" }
  vim.list_extend(head, opts.headers or {})
  if opts.body then
    table.insert(head, "Content-Length: " .. #opts.body)
  end
  client:write(table.concat(head, "\r\n") .. "\r\n\r\n" .. (opts.body or ""))
  client:shutdown(function()
    client:close()
  end)
end

---Write each line on its own timer tick until the lines run out or the client goes away
---@param client uv.uv_tcp_t
---@param opts { lines: string[], forever?: boolean }
local function stream(client, opts)
  client:write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
  local timer, index = assert(vim.uv.new_timer()), 0
  timer:start(20, 20, function()
    index = index + 1
    local line = opts.lines[opts.forever and 1 or index]
    if not line or client:is_closing() then
      timer:close()
      return client:is_closing() or client:shutdown(function()
        client:close()
      end)
    end
    client:write(line, function(err)
      if err and not client:is_closing() then
        client:close()
      end
    end)
  end)
end

local ROUTES = {
  ["/json"] = function(client)
    respond(client, { status = "200 OK", headers = { "Content-Type: application/json" }, body = '{"ok":true}' })
  end,
  ["/echo"] = function(client, body)
    respond(client, { status = "200 OK", body = body })
  end,
  ["/redirect"] = function(client)
    respond(client, { status = "302 Found", headers = { "Location: /json" }, body = "" })
  end,
  ["/stream"] = function(client)
    stream(client, { lines = { 'data: {"a"', ':1}\n\ndata: {"b"', ":2}\n\ndata: [DONE]" } })
  end,
  ["/forever"] = function(client)
    stream(client, { lines = { "data: tick\n" }, forever = true })
  end,
  ["/silent"] = function() end,
}

---Answer each request once its headers and Content-Length body have arrived
---@param client uv.uv_tcp_t
local function handle_client(client)
  local received = ""
  client:read_start(function(_, chunk)
    if not chunk then
      return client:is_closing() or client:close()
    end
    received = received .. chunk
    local head_end = received:find("\r\n\r\n", 1, true)
    local length = tonumber(received:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")) or 0
    if not head_end or #received < head_end + 3 + length then
      return
    end
    client:read_stop()
    ROUTES[received:match("^%u+ (%S+)")](client, received:sub(head_end + 4, head_end + 3 + length))
  end)
end

T["Curl"] = new_set({
  hooks = {
    pre_once = function()
      -- Load the module afresh, as minimal_init.lua blocks real requests on the shared one
      local guarded = package.loaded["codecompanion.utils.curl"]
      package.loaded["codecompanion.utils.curl"] = nil
      curl = require("codecompanion.utils.curl")
      package.loaded["codecompanion.utils.curl"] = guarded

      server = assert(vim.uv.new_tcp())
      server:bind("127.0.0.1", 0)
      server:listen(16, function()
        local client = assert(vim.uv.new_tcp())
        server:accept(client)
        handle_client(client)
      end)
      base_url = "http://127.0.0.1:" .. server:getsockname().port
    end,
    post_once = function()
      server:close()
    end,
  },
})

---@param opts CodeCompanion.Curl.Opts
---@return { lines: string[], response?: CodeCompanion.Curl.Response, err?: CodeCompanion.Curl.Error, job: CodeCompanion.Curl.Job }
local function request_async(opts)
  local outcome = { lines = {} }
  outcome.job = curl.get(vim.tbl_extend("force", {
    stream = function(line)
      table.insert(outcome.lines, line)
    end,
    callback = function(response)
      outcome.response = response
    end,
    on_error = function(err)
      outcome.err = err
    end,
  }, opts))
  return outcome
end

---@param outcome { response?: CodeCompanion.Curl.Response, err?: CodeCompanion.Curl.Error }
local function wait_for(outcome)
  vim.wait(5000, function()
    return outcome.response ~= nil or outcome.err ~= nil
  end)
end

T["Curl"]["sends a string body and reads the response"] = function()
  local response = curl.post_sync({ url = base_url .. "/echo", body = '{"text":"a\\nb"}\n{"x":1}' })

  h.eq(response.status, 200)
  h.eq(response.body, '{"text":"a\\nb"}\n{"x":1}')
end

T["Curl"]["sends a body file from a temp path"] = function()
  local body_file = vim.fn.tempname() .. ".json"
  vim.fn.writefile({ '{"from":"file"}' }, body_file)

  local response = curl.post_sync({ url = base_url .. "/echo", body_file = body_file })

  h.eq(response.body, '{"from":"file"}\n')
end

T["Curl"]["follows a redirect and reports the FINAL status"] = function()
  local response = curl.get_sync({ url = base_url .. "/redirect" })

  h.eq(response.status, 200)
  h.eq(response.body, '{"ok":true}')
  h.eq(vim.tbl_contains(response.headers, "Location: /json"), true)
  h.eq(vim.tbl_contains(response.headers, "Content-Type: application/json"), true)
end

T["Curl"]["streams lines split across network writes"] = function()
  local outcome = request_async({ url = base_url .. "/stream", raw = { "--no-buffer" } })
  wait_for(outcome)

  h.eq(outcome.lines, { 'data: {"a":1}', "", 'data: {"b":2}', "", "data: [DONE]" })
  h.eq(outcome.response.status, 200)
  h.eq(outcome.response.body, 'data: {"a":1}\n\ndata: {"b":2}\n\ndata: [DONE]')
end

T["Curl"]["downloads to an output file"] = function()
  local output = vim.fn.tempname()
  local outcome = request_async({ url = base_url .. "/json", output = output, stream = nil })
  wait_for(outcome)

  h.eq(outcome.response.status, 200)
  h.eq(vim.fn.readfile(output), { '{"ok":true}' })
end

T["Curl"]["passes a cancelled stream to on_error"] = function()
  local outcome = request_async({ url = base_url .. "/forever", raw = { "--no-buffer" } })
  vim.wait(5000, function()
    return #outcome.lines > 0
  end)
  outcome.job.shutdown()
  wait_for(outcome)

  h.eq(outcome.response, nil)
  h.expect_contains("signal=15", outcome.err.message)
end

T["Curl"]["passes a refused connection to on_error"] = function()
  local closed = assert(vim.uv.new_tcp())
  closed:bind("127.0.0.1", 0)
  local port = closed:getsockname().port
  closed:close()

  local outcome = request_async({ url = "http://127.0.0.1:" .. port .. "/json" })
  wait_for(outcome)

  h.eq(outcome.response, nil)
  h.eq(outcome.err.exit, 7)
end

T["Curl"]["times out a blocking request"] = function()
  local response, err = curl.get_sync({ url = base_url .. "/silent", timeout = 500 })

  h.eq(response, nil)
  h.eq(err.exit, 124)
end

local path

T["Curl"]["without curl on the PATH"] = new_set({
  hooks = {
    pre_case = function()
      path = vim.env.PATH
      vim.env.PATH = ""
    end,
    post_case = function()
      vim.env.PATH = path
    end,
  },
})

T["Curl"]["without curl on the PATH"]["returns an error from a BLOCKING request"] = function()
  local response, err = curl.get_sync({ url = base_url .. "/json" })

  h.eq(response, nil)
  h.expect_contains("could not start curl", err.message)
end

T["Curl"]["without curl on the PATH"]["passes to on_error from an ASYNC request"] = function()
  local outcome = request_async({ url = base_url .. "/json" })
  wait_for(outcome)

  h.eq(outcome.response, nil)
  h.expect_contains("could not start curl", outcome.err.message)
end

return T
