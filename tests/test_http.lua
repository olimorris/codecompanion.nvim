local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        -- Counters maintained by the default POST/GET stubs
        _G.__calls = { get = 0, post = 0 }

        -- Factory for a minimal adapter
        _G.__make_adapter = function(overrides)
          local base = {
            name = "TestAdapter",
            url = "https://api.openai.com/v1/${url_value}/completions",
            env = {
              url_value = "chat",
              header_value = "json",
              raw_value = "RAW_VALUE",
            },
            headers = {
              content_type = "application/${header_value}",
            },
            raw = {
              "--arg1-${raw_value}",
              "--arg2-${raw_value}",
            },
            handlers = {
              form_parameters = function() return {} end,
              form_messages = function() return {} end,
            },
            schema = { model = { default = "my_model" } },
            opts = { method = "POST", stream = false },
          }
          if overrides then
            base = vim.tbl_deep_extend("force", base, overrides)
          end
          local adapter = require("codecompanion.adapters").resolve(base)
          -- Populate env_replaced so the adapter is request-ready (set_env_vars needs it)
          return require("codecompanion.adapters.utils").get_env_vars(adapter)
        end

        -- Load client and make scheduling immediate for deterministic tests
        _G.Client = require("codecompanion.http")

        -- Always encode with vim.json.encode so body file is valid
        _G.Client.static.methods.encode = {
          default = function(tbl) return vim.json.encode(tbl) end,
        }
        -- Make schedule and schedule_wrap synchronous
        _G.Client.static.methods.schedule = { default = function(fn) fn() end }
        _G.Client.static.methods.schedule_wrap = {
          default = function(fn) return function(...) return fn(...) end end,
        }

        -- Default POST/GET stubs (can be overridden per test)
        _G.Client.static.methods.post = {
          default = function(opts)
            _G.__calls.post = _G.__calls.post + 1
            _G.__last_request_opts = opts
            return { args = "mocked args", shutdown = function() end }
          end,
        }
        _G.Client.static.methods.get = {
          default = function(opts)
            _G.__calls.get = _G.__calls.get + 1
            _G.__last_request_opts = opts
            return { args = "mocked args", shutdown = function() end }
          end,
        }
      ]])
    end,
    post_once = child.stop,
  },
})

T["can call POST API endpoint"] = function()
  child.lua([[
    local adapter = __make_adapter()
    local cb = function() end
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})
  ]])

  h.eq(child.lua_get([[_G.__calls.post]]), 1)
end

T["resolve_method defaults to post and lowercases the adapter override"] = function()
  local result = child.lua([[
    return {
      default = Client.resolve_method(__make_adapter()),
      get = Client.resolve_method(__make_adapter({ opts = { method = "GET" } })),
    }
  ]])

  h.eq(result.default, "post")
  h.eq(result.get, "get")
end

T["build_curl_args writes headers to a temp file with env vars substituted, one per line"] = function()
  local header_path = child.lua([[
    local _, headers_file = Client.build_curl_args(__make_adapter())
    return headers_file
  ]])

  local lines = vim.fn.readfile(header_path)
  h.eq(#lines > 0, true)
  h.eq(vim.tbl_contains(lines, "content_type: application/json"), true)
  for _, line in ipairs(lines) do
    h.eq(line:match("^[^:]+: .+") ~= nil, true)
  end
end

T["build_curl_args passes the headers file via --header @file and substitutes adapter.raw"] = function()
  local raw = child.lua([[
    local raw = Client.build_curl_args(__make_adapter())
    return raw
  ]])

  -- --header @file is the last two entries, keeping headers out of the process args
  h.eq(raw[#raw - 1], "--header")
  h.eq(raw[#raw]:match("^@.+%.headers$") ~= nil, true)

  -- adapter.raw entries (env substituted) come before --header @file
  h.eq(raw[#raw - 3], "--arg1-RAW_VALUE")
  h.eq(raw[#raw - 2], "--arg2-RAW_VALUE")
end

T["build_curl_args adds streaming flags only when stream is set"] = function()
  local result = child.lua([[
    local without = Client.build_curl_args(__make_adapter())
    local with = Client.build_curl_args(__make_adapter(), { stream = true })
    return {
      without_nodelay = vim.tbl_contains(without, "--tcp-nodelay"),
      with_nodelay = vim.tbl_contains(with, "--tcp-nodelay"),
      with_nobuffer = vim.tbl_contains(with, "--no-buffer"),
    }
  ]])

  h.eq(result.without_nodelay, false)
  h.eq(result.with_nodelay, true)
  h.eq(result.with_nobuffer, true)
end

T["request substitutes the url and installs a stream handler when streaming"] = function()
  child.lua([[
    local adapter = __make_adapter({ opts = { method = "POST", stream = true, compress = false } })
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = function() end }, {})
  ]])

  h.eq(child.lua_get([[ _G.__last_request_opts.url ]]), "https://api.openai.com/v1/chat/completions")
  h.eq(child.lua_get([[ type(_G.__last_request_opts.headers) ]]), "nil")
  h.eq(child.lua_get([[ type(_G.__last_request_opts.stream) ]]), "function")
  h.eq(child.lua_get([[ _G.__last_request_opts.compressed ]]), false)
end

T["dispatches GET when method is GET"] = function()
  child.lua([[
    local adapter = __make_adapter({ opts = { method = "GET", stream = false } })
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = function() end }, {})
  ]])

  h.eq(child.lua_get([[_G.__calls.get]]), 1)
  h.eq(child.lua_get([[_G.__calls.post]]), 0)
end

T["invokes on_error callback with error"] = function()
  local result = child.lua([[
    -- Override POST to trigger on_error
    _G.Client.static.methods.post = {
      default = function(opts)
        opts.on_error({ message = "boom", stderr = "boom" })
        return { args = "mocked args", shutdown = function() end }
      end,
    }

    local adapter = __make_adapter()
    local err_received
    local cb = function(err, _)
      err_received = err and err.message or nil
    end
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})

    return { err_received = err_received }
  ]])

  h.eq(result.err_received, "boom")
end

T["calls done then emits error callback for HTTP status >= 400"] = function()
  local result = child.lua([[
    -- Override POST to simulate a non-streaming 500 response
    _G.Client.static.methods.post = {
      default = function(opts)
        opts.callback({ status = 500 })
        return { args = "mocked args", shutdown = function() end }
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local callback_calls = 0
    local err_received
    local cb = function(err, _)
      callback_calls = callback_calls + 1
      if err then err_received = err.message end
    end
    local done_called = false
    local done = function() done_called = true end

    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb, done = done }, {})

    return { callback_calls = callback_calls, done_called = done_called, err_received = err_received }
  ]])

  h.eq(result.done_called, true)
  h.eq(result.callback_calls, 2)
  h.eq(result.err_received, "500 error: ")
end

T["send_sync returns response on success"] = function()
  local result = child.lua([[
    -- Override POST to return a synchronous success response
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        return { status = 200, headers = { "OK" }, body = "ok", exit = 0 }
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local resp, err = Client.new({ adapter = adapter }):send_sync({ messages = {}, tools = {} }, { stream = false, silent = true, timeout = 100 })

    return {
      body = resp and resp.body or nil,
      err_is_nil = err == nil,
      post = _G.__calls.post,
      status = resp and resp.status or nil,
    }
  ]])

  h.eq(result.post, 1)
  h.eq(result.status, 200)
  h.eq(result.body, "ok")
  h.eq(result.err_is_nil, true)
end

T["send_sync returns error on HTTP status >= 400"] = function()
  local result = child.lua([[
    -- Override POST to return a synchronous 500 response
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        return { status = 500, headers = { "ERR" }, body = "boom", exit = 0 }
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local resp, err = Client.new({ adapter = adapter }):send_sync({ messages = {}, tools = {} }, { stream = false, silent = true, timeout = 100 })

    return {
      err_message = err and err.message or nil,
      post = _G.__calls.post,
      resp_is_nil = resp == nil,
    }
  ]])

  h.eq(result.post, 1)
  h.eq(result.resp_is_nil, true)
  h.eq(result.err_message, "500 error: ")
end

T["send_sync returns error when curl call fails"] = function()
  local result = child.lua([[
    -- Override POST to simulate a thrown error in curl
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        error("curl failed")
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local resp, err = Client.new({ adapter = adapter }):send_sync({ messages = {}, tools = {} }, { stream = false, silent = true, timeout = 100 })

    return {
      err_message = err and err.message or nil,
      post = _G.__calls.post,
      resp_is_nil = resp == nil,
    }
  ]])

  h.eq(result.post, 1)
  h.eq(result.resp_is_nil, true)
  h.expect_contains("curl failed", result.err_message)
end

T["send_sync merges structured output schema into the request body"] = function()
  local result = child.lua([[
    local captured_body
    _G.Client.static.methods.encode = {
      default = function(tbl) captured_body = tbl; return vim.json.encode(tbl) end,
    }
    _G.Client.static.methods.post = {
      default = function(opts)
        return { status = 200, headers = {}, body = "ok", exit = 0 }
      end,
    }

    local adapter = __make_adapter({
      opts = { method = "POST", stream = false },
      handlers = {
        form_structured_output = function(self, schema)
          return { response_format = { type = "json_schema", json_schema = { name = schema.name } } }
        end,
      },
    })

    local structured_output = { name = "weather", strict = true, schema = { type = "object" } }
    local resp, err = Client.new({ adapter = adapter }):send_sync(
      { messages = {}, tools = {}, structured_output = structured_output },
      { stream = false, silent = true, timeout = 100 }
    )

    return {
      err_is_nil = err == nil,
      response_format = captured_body and captured_body.response_format or nil,
    }
  ]])

  h.eq(result.err_is_nil, true)
  h.eq(result.response_format.type, "json_schema")
  h.eq(result.response_format.json_schema.name, "weather")
end

T["merge_body deep-merges colliding body keys from different handlers"] = function()
  -- Regression: OpenAI Responses maps `verbosity` to body.text while structured
  -- output writes to text.format. A shallow merge silently dropped the latter.
  local result = child.lua([[
    local adapter = {
      parameters = {},
      handlers = {
        form_parameters = function() return { text = { verbosity = "medium" } } end,
        form_structured_output = function() return { text = { format = { type = "json_schema" } } } end,
      },
    }
    local body = Client.merge_body(adapter, { structured_output = { name = "weather" } })
    return { verbosity = body.text.verbosity, format_type = body.text.format.type }
  ]])

  h.eq(result.verbosity, "medium")
  h.eq(result.format_type, "json_schema")
end

T["send_sync returns error when adapter does not support structured outputs"] = function()
  local result = child.lua([[
    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local structured_output = { name = "weather", schema = { type = "object" } }
    local resp, err = Client.new({ adapter = adapter }):send_sync(
      { messages = {}, structured_output = structured_output },
      { stream = false, silent = true, timeout = 100 }
    )

    return {
      resp_is_nil = resp == nil,
      err_message = err and err.message or nil,
      post = _G.__calls.post,
    }
  ]])

  h.eq(result.resp_is_nil, true)
  h.eq(result.post, 0)
  h.expect_contains("does not support structured outputs", result.err_message)
end

T["handles nil data with captured stream error"] = function()
  local result = child.lua([[
    _G.Client.static.methods.post = {
      default = function(opts)
        if opts.stream then
          opts.stream(nil, '{"error": {"message": "Insufficient credits"}}')
        end
        opts.callback(nil)
        return { args = "mocked args", shutdown = function() end }
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = true } })
    local err_received
    local cb = function(err, _)
      if err then err_received = err.message end
    end

    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})

    return { err_received = err_received }
  ]])

  h.eq(result.err_received, "Request failed")
end

return T
