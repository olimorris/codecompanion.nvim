local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set()

T["Curl"] = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        package.loaded["codecompanion.utils.curl"] = nil
        _G.curl = require("codecompanion.utils.curl")

        -- Replays `_G.process` through the same callbacks vim.system would call
        _G.process = { chunks = {}, headers = { "HTTP/1.1 200 OK" }, code = 0, signal = 0, stderr = "" }
        _G.spawned = {}
        vim.system = function(args, opts, on_exit)
          table.insert(_G.spawned, { args = args, opts = opts })
          if _G.process.fails_to_start then
            error("ENOENT: no such file or directory")
          end

          local headers_file = args[vim.fn.index(args, "--dump-header") + 2]
          vim.fn.writefile(_G.process.headers, headers_file)
          local result = { code = _G.process.code, signal = _G.process.signal, stderr = _G.process.stderr }

          if not on_exit then
            result.stdout = table.concat(_G.process.chunks)
            return { wait = function() return result end }
          end

          for _, chunk in ipairs(_G.process.chunks) do
            opts.stdout(nil, chunk)
          end
          opts.stdout(nil, nil)
          on_exit(result)
          return { kill = function() end }
        end

        _G.events = {}
        _G.request_async = function(opts)
          local finished = false
          curl.post(vim.tbl_extend("force", {
            url = "https://example.com",
            stream = function(_, line) table.insert(_G.events, line) end,
            callback = function(response) table.insert(_G.events, "callback"); _G.response = response; finished = true end,
            on_error = function(err) table.insert(_G.events, "on_error"); _G.err = err; finished = true end,
          }, opts or {}))
          vim.wait(1000, function() return finished end)
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Curl"]["streams a line SPLIT across chunks as one line"] = function()
  child.lua([[
    _G.process.chunks = { 'data: {"a"', ':1}\n\ndata: {"b":2}\n' }
    request_async()
  ]])

  h.eq(child.lua_get("_G.events"), { 'data: {"a":1}', "", 'data: {"b":2}', "callback" })
end

T["Curl"]["streams the final line when it has NO trailing newline"] = function()
  child.lua([[
    _G.process.chunks = { "data: one\n", "data: [DONE]" }
    request_async()
  ]])

  h.eq(child.lua_get("_G.events"), { "data: one", "data: [DONE]", "callback" })
end

T["Curl"]["passes the whole body to the callback after streaming"] = function()
  child.lua([[
    _G.process.chunks = { "data: one\n", "data: two\n" }
    request_async()
  ]])

  h.eq(child.lua_get("_G.response.body"), "data: one\ndata: two\n")
end

T["Curl"]["sends a string body through stdin"] = function()
  local spawned = child.lua([[
    curl.post({ url = "https://example.com", body = '{"model":"gpt"}' })
    return _G.spawned[1]
  ]])

  h.eq(spawned.opts.stdin, '{"model":"gpt"}')
  h.expect_contains("--data-binary @-", table.concat(spawned.args, " "))
end

T["Curl"]["sends a body file by its path"] = function()
  local spawned = child.lua([[
    curl.post({ url = "https://example.com", body_file = "/tmp/request.json" })
    return _G.spawned[1]
  ]])

  h.eq(spawned.opts.stdin, nil)
  h.expect_contains("--data-binary @/tmp/request.json", table.concat(spawned.args, " "))
end

T["Curl"]["reads the status of the FINAL response after a redirect"] = function()
  local response = child.lua([[
    _G.process.headers = {
      "HTTP/1.1 302 Found",
      "Location: /final",
      "",
      "HTTP/2 200",
      "content-type: application/json",
      "",
    }
    _G.process.chunks = { '{"ok":true}' }
    return curl.get({ url = "https://example.com" })
  ]])

  h.eq(response.status, 200)
  h.eq(response.headers, { "Location: /final", "content-type: application/json" })
  h.eq(response.body, '{"ok":true}')
end

T["Curl"]["passes a curl failure to on_error, NOT the callback"] = function()
  child.lua([[
    _G.process.code = 7
    _G.process.stderr = "curl: (7) Failed to connect"
    request_async()
  ]])

  h.eq(child.lua_get("_G.events"), { "on_error" })
  h.eq(child.lua_get("_G.err.exit"), 7)
  h.expect_contains("Failed to connect", child.lua_get("_G.err.message"))
end

T["Curl"]["passes a killed request to on_error"] = function()
  child.lua([[
    _G.process.signal = 15
    request_async()
  ]])

  h.eq(child.lua_get("_G.events"), { "on_error" })
  h.expect_contains("signal=15", child.lua_get("_G.err.message"))
end

T["Curl"]["returns the error from a blocking request that fails"] = function()
  local result = child.lua([[
    _G.process.code = 28
    local response, err = curl.get({ url = "https://example.com" })
    return { response = response or vim.NIL, exit = err.exit }
  ]])

  h.eq(result, { response = vim.NIL, exit = 28 })
end

T["Curl"]["returns an error when curl cannot start a BLOCKING request"] = function()
  local result = child.lua([[
    _G.process.fails_to_start = true
    local response, err = curl.get({ url = "https://example.com" })
    return { response = response or vim.NIL, message = err.message }
  ]])

  h.eq(result.response, vim.NIL)
  h.expect_contains("could not start curl", result.message)
end

T["Curl"]["passes to on_error when curl cannot start an ASYNC request"] = function()
  child.lua([[
    _G.process.fails_to_start = true
    request_async()
  ]])

  h.eq(child.lua_get("_G.events"), { "on_error" })
  h.expect_contains("could not start curl", child.lua_get("_G.err.message"))
end

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

T["Curl against a local server"] = new_set({
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
    stream = function(_, line)
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

T["Curl against a local server"]["sends a string body and reads the response"] = function()
  local response = curl.post({ url = base_url .. "/echo", body = '{"text":"a\\nb"}\n{"x":1}' })

  h.eq(response.status, 200)
  h.eq(response.body, '{"text":"a\\nb"}\n{"x":1}')
end

T["Curl against a local server"]["sends a body file from a temp path"] = function()
  local body_file = vim.fn.tempname() .. ".json"
  vim.fn.writefile({ '{"from":"file"}' }, body_file)

  local response = curl.post({ url = base_url .. "/echo", body_file = body_file })

  h.eq(response.body, '{"from":"file"}\n')
end

T["Curl against a local server"]["follows a redirect and reports the FINAL status"] = function()
  local response = curl.get({ url = base_url .. "/redirect" })

  h.eq(response.status, 200)
  h.eq(response.body, '{"ok":true}')
  h.eq(vim.tbl_contains(response.headers, "Location: /json"), true)
  h.eq(vim.tbl_contains(response.headers, "Content-Type: application/json"), true)
end

T["Curl against a local server"]["streams lines split across network writes"] = function()
  local outcome = request_async({ url = base_url .. "/stream", raw = { "--no-buffer" } })
  wait_for(outcome)

  h.eq(outcome.lines, { 'data: {"a":1}', "", 'data: {"b":2}', "", "data: [DONE]" })
  h.eq(outcome.response.status, 200)
end

T["Curl against a local server"]["downloads to an output file"] = function()
  local output = vim.fn.tempname()
  local outcome = request_async({ url = base_url .. "/json", output = output, stream = nil })
  wait_for(outcome)

  h.eq(outcome.response.status, 200)
  h.eq(vim.fn.readfile(output), { '{"ok":true}' })
end

T["Curl against a local server"]["passes a cancelled stream to on_error"] = function()
  local outcome = request_async({ url = base_url .. "/forever", raw = { "--no-buffer" } })
  vim.wait(5000, function()
    return #outcome.lines > 0
  end)
  outcome.job.shutdown()
  wait_for(outcome)

  h.eq(outcome.response, nil)
  h.expect_contains("signal=15", outcome.err.message)
end

T["Curl against a local server"]["passes a refused connection to on_error"] = function()
  local closed = assert(vim.uv.new_tcp())
  closed:bind("127.0.0.1", 0)
  local port = closed:getsockname().port
  closed:close()

  local outcome = request_async({ url = "http://127.0.0.1:" .. port .. "/json" })
  wait_for(outcome)

  h.eq(outcome.err.exit, 7)
end

T["Curl against a local server"]["times out a blocking request"] = function()
  local response, err = curl.get({ url = base_url .. "/silent", timeout = 500 })

  h.eq(response, nil)
  h.eq(err.exit, 124)
end

return T
