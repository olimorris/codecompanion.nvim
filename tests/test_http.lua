local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        _G.__calls = {
          post = 0,
          get = 0,
          shutdown_called = false,
          err_received = nil,
          callback_calls = 0,
          done_called = false,
        }

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
          return require("codecompanion.adapters").resolve(base)
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
            return { args = "mocked args", shutdown = function() _G.__calls.shutdown_called = true end }
          end,
        }
        _G.Client.static.methods.get = {
          default = function(opts)
            _G.__calls.get = _G.__calls.get + 1
            _G.__last_request_opts = opts
            return { args = "mocked args", shutdown = function() _G.__calls.shutdown_called = true end }
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
    local cb = function() _G.__calls.callback_calls = _G.__calls.callback_calls + 1 end
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})
  ]])

  h.eq(child.lua_get([[_G.__calls.post]]), 1)
end

T["substitutes variables in url, headers, and raw"] = function()
  child.lua([[
    local adapter = __make_adapter()
    local cb = function() end
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})
  ]])

  h.eq(child.lua_get([[ _G.__last_request_opts.url ]]), "https://api.openai.com/v1/chat/completions")
  h.eq(child.lua_get([[ _G.__last_request_opts.headers.content_type ]]), "application/json")
  local last1 = child.lua_get([[ _G.__last_request_opts.raw[#_G.__last_request_opts.raw - 1] ]])
  local last2 = child.lua_get([[ _G.__last_request_opts.raw[#_G.__last_request_opts.raw] ]])
  h.eq(last1, "--arg1-RAW_VALUE")
  h.eq(last2, "--arg2-RAW_VALUE")
end

T["adds streaming flags and stream handler when stream=true"] = function()
  child.lua([[
    local adapter = __make_adapter({ opts = { method = "POST", stream = true, compress = false } })
    local cb = function() end
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})
  ]])

  h.eq(child.lua_get([[ type(_G.__last_request_opts.stream) ]]), "function")
  h.eq(child.lua_get([[ _G.__last_request_opts.compressed ]]), false)

  local has_nodelay = child.lua_get([[ vim.tbl_contains(_G.__last_request_opts.raw, "--tcp-nodelay") ]])
  local has_nobuffer = child.lua_get([[ vim.tbl_contains(_G.__last_request_opts.raw, "--no-buffer") ]])
  h.eq(has_nodelay, true)
  h.eq(has_nobuffer, true)
end

T["dispatches GET when method is GET"] = function()
  child.lua([[
    local adapter = __make_adapter({ opts = { method = "GET", stream = false } })
    local cb = function() end
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})
  ]])

  h.eq(child.lua_get([[_G.__calls.get]]), 1)
  h.eq(child.lua_get([[_G.__calls.post]]), 0)
end

T["invokes on_error callback with error"] = function()
  child.lua([[
    -- Override POST to trigger on_error
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        _G.__last_request_opts = opts
        opts.on_error({ message = "boom", stderr = "boom" })
        return { args = "mocked args", shutdown = function() end }
      end,
    }

    local adapter = __make_adapter()
    local cb = function(err, _)
      _G.__calls.err_received = err and err.message or nil
    end
    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb }, {})

    -- schedule is synchronous, but keep a small wait for safety
    vim.wait(10, function() return _G.__calls.err_received ~= nil end, 1)
  ]])

  h.eq(child.lua_get([[_G.__calls.err_received]]), "boom")
end

T["calls done then emits error callback for HTTP status >= 400"] = function()
  child.lua([[
    -- Override POST to simulate a non-streaming 500 response
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        _G.__last_request_opts = opts
        opts.callback({ status = 500 })
        return { args = "mocked args", shutdown = function() end }
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local cb = function(err, _)
      _G.__calls.callback_calls = _G.__calls.callback_calls + 1
      if err then _G.__calls.err_received = err.message end
    end
    local done = function() _G.__calls.done_called = true end

    Client.new({ adapter = adapter }):request({ messages = {}, tools = {} }, { callback = cb, done = done }, {})

    vim.wait(20, function()
      return _G.__calls.done_called == true and _G.__calls.callback_calls >= 2 and _G.__calls.err_received ~= nil
    end, 1)
  ]])

  h.eq(child.lua_get([[_G.__calls.done_called]]), true)
  h.eq(child.lua_get([[_G.__calls.callback_calls]]), 2)
  h.eq(child.lua_get([[_G.__calls.err_received]]), "500 error: ")
end

T["send_sync returns response on success"] = function()
  child.lua([[
    -- Override POST to return a synchronous success response
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        _G.__last_request_opts = opts
        return { status = 200, headers = { "OK" }, body = "ok", exit = 0 }
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local resp, err = Client.new({ adapter = adapter }):send_sync({ messages = {}, tools = {} }, { stream = false, silent = true, timeout = 100 })

    _G.__sync_resp_status = resp and resp.status or nil
    _G.__sync_resp_body = resp and resp.body or nil
    _G.__sync_err_is_nil = (err == nil)
  ]])

  h.eq(child.lua_get([[_G.__calls.post]]), 1)
  h.eq(child.lua_get([[_G.__sync_resp_status]]), 200)
  h.eq(child.lua_get([[_G.__sync_resp_body]]), "ok")
  h.eq(child.lua_get([[_G.__sync_err_is_nil]]), true)
end

T["send_sync returns error on HTTP status >= 400"] = function()
  child.lua([[
    -- Override POST to return a synchronous 500 response
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        _G.__last_request_opts = opts
        return { status = 500, headers = { "ERR" }, body = "boom", exit = 0 }
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local resp, err = Client.new({ adapter = adapter }):send_sync({ messages = {}, tools = {} }, { stream = false, silent = true, timeout = 100 })

    _G.__sync_resp_is_nil = (resp == nil)
    _G.__sync_err_message = err and err.message or nil
  ]])

  h.eq(child.lua_get([[_G.__calls.post]]), 1)
  h.eq(child.lua_get([[_G.__sync_resp_is_nil]]), true)
  h.eq(child.lua_get([[_G.__sync_err_message]]), "500 error: ")
end

T["send_sync returns error when curl call fails"] = function()
  child.lua([[
    -- Override POST to simulate a thrown error in curl
    _G.Client.static.methods.post = {
      default = function(opts)
        _G.__calls.post = _G.__calls.post + 1
        _G.__last_request_opts = opts
        error("curl failed")
      end,
    }

    local adapter = __make_adapter({ opts = { method = "POST", stream = false } })
    local resp, err = Client.new({ adapter = adapter }):send_sync({ messages = {}, tools = {} }, { stream = false, silent = true, timeout = 100 })

    _G.__sync_resp_is_nil = (resp == nil)
    _G.__sync_err_message = err and err.message or nil
  ]])

  h.eq(child.lua_get([[_G.__calls.post]]), 1)
  h.eq(child.lua_get([[_G.__sync_resp_is_nil]]), true)
  h.expect_contains("curl failed", child.lua_get([[_G.__sync_err_message]]))
end

return T
