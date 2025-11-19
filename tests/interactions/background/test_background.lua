local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        h.setup_plugin()
      ]])

      h.create_mock_adapter(child)
      h.mock_http(child)

      child.lua([[b = require("codecompanion.interactions.background")]])
    end,
    post_once = child.stop,
  },
})

T["Background"] = new_set()
T["Background"]["ask"] = new_set()

T["Background"]["ask"]["performs sync requests"] = function()
  -- Queue response
  child.lua([[
    _G.mock_client:queue_response({
      body = vim.json.encode({
        choices = {
          {
            message = {
              content = "Test response from LLM",
            },
          },
        },
      }),
    })
  ]])

  child.lua([[
    background = b.new({
      adapter = _G.mock_adapter
    })

    local messages = { { role = "user", content = "Test message" } }
    _G.result, _G.err = background:ask(messages, { method = "sync", silent = true })
  ]])

  local requests = h.get_mock_http_requests(child)

  h.eq(#requests, 1)
  h.eq(requests[1].type, "sync")
  h.expect_contains("user", requests[1].payload.messages[1].role)
  h.expect_contains("Test message", requests[1].payload.messages[1].content)

  local result = child.lua_get("_G.result")

  h.eq(result.status, "success")
  h.eq(result.output.content, "Test response from LLM")
end

T["Background"]["ask"]["handles sync errors"] = function()
  -- Don't queue a response - mock will return error
  child.lua([[
    background = b.new({ adapter = _G.mock_adapter })
    local messages = { { role = "user", content = "Test" } }
    _G.result, _G.err = background:ask(messages, { method = "sync", silent = true })
  ]])

  local result = child.lua_get("_G.result")
  local err = child.lua_get("_G.err")

  h.eq(result, vim.NIL)
  h.expect_truthy(err)
  h.expect_contains("No queued response", err.message)
end

T["Background"]["ask"]["performs async requests"] = function()
  child.lua([[
    _G.mock_client:queue_response({
      body = vim.json.encode({
        choices = {
          {
            message = {
              content = "Async response",
            },
          },
        },
      }),
    })
  ]])

  child.lua([[
    background = b.new({ adapter = _G.mock_adapter })
    local messages = { { role = "user", content = "Async test" } }

    _G.async_result = nil
    _G.async_called = false

    background:ask(messages, {
      method = "async",
      silent = true,
      on_done = function(result, meta)
        _G.async_called = true
        _G.async_result = result
      end,
    })
  ]])

  -- Wait for async callback
  vim.wait(100, function()
    return child.lua_get("_G.async_called") == true
  end)

  local async_called = child.lua_get("_G.async_called")
  local async_result = child.lua_get("_G.async_result")

  h.is_true(async_called)
  h.expect_truthy(async_result)
  h.eq(async_result.status, "success")
  h.eq(async_result.output.content, "Async response")
end

return T
