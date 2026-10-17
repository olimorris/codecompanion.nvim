local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
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
          return { is_closing = function() return true end, kill = function() end }
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

T["Curl"] = new_set()

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

T["Curl"]["returns an error when curl cannot start"] = function()
  local result = child.lua([[
    _G.process.fails_to_start = true
    local blocking, blocking_err = curl.get({ url = "https://example.com" })
    local job, async_err = curl.get({ url = "https://example.com", callback = function() end })
    return {
      blocking = blocking or vim.NIL,
      job = job or vim.NIL,
      blocking_message = blocking_err.message,
      async_message = async_err.message,
    }
  ]])

  h.eq(result.blocking, vim.NIL)
  h.eq(result.job, vim.NIL)
  h.expect_contains("could not start curl", result.blocking_message)
  h.expect_contains("could not start curl", result.async_message)
end

return T
