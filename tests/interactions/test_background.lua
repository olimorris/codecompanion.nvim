local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Background"] = new_set()

T["Background"]["new()"] = new_set()

T["Background"]["new()"]["creates background instance with default adapter"] = function()
  child.lua([[
    -- Setup config FIRST
    local test_config = vim.deepcopy(config)
    local config_module = require("codecompanion.config")
    config_module.setup(test_config)

    -- Now require Background after config is set up
    local Background = require("codecompanion.interactions.background")

    local bg = Background.new()
    _G.bg_result = {
      id = bg.id,
      messages = bg.messages,
      adapter_name = bg.adapter.name,
      adapter_type = bg.adapter.type,
      settings = bg.settings,
      default_adapter = config_module.strategies.chat.adapter
    }
  ]])

  local result = child.lua_get("_G.bg_result")
  h.expect_truthy(result.id)
  h.eq(result.messages, {})
  h.eq(result.adapter_name, result.default_adapter) -- Should match whatever the default is
  h.eq(result.adapter_type, "http")
  h.expect_truthy(result.settings)
end

T["Background"]["new()"]["creates background instance with custom adapter"] = function()
  -- Skip this test for now due to adapter resolution issues in test environment
  MiniTest.skip("Adapter resolution issues in test environment")
end

T["Background"]["new()"]["creates background instance with initial messages"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    local messages = {
      { role = "user", content = "Hello" },
      { role = "assistant", content = "Hi there!" }
    }
    local bg = Background.new({ messages = messages })
    _G.bg_result = bg.messages
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result, {
    { role = "user", content = "Hello" },
    { role = "assistant", content = "Hi there!" },
  })
end

T["Background"]["new()"]["errors with non-HTTP adapter"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")

    -- Setup config with test adapter
    local test_config = vim.deepcopy(config)
    local config_module = require("codecompanion.config")
    config_module.setup(test_config)

    -- Mock an ACP adapter
    local mock_adapter = { type = "acp", name = "test_acp" }
    local adapters = require("codecompanion.adapters")
    local original_resolve = adapters.resolve
    adapters.resolve = function() return mock_adapter end

    local bg = Background.new({ adapter = "test_acp" })
    _G.bg_result = bg or "nil_value" -- Convert nil to string for transport

    -- Restore original function
    adapters.resolve = original_resolve
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result, "nil_value") -- Should return nil due to error
end

T["Background"]["ask_sync()"] = new_set()

T["Background"]["ask_sync()"]["works with provided messages"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    -- Mock the HTTP client to avoid actual API calls
    local http = require("codecompanion.http")
    local original_new = http.new
    http.new = function(opts)
      local client = original_new(opts)
      client.send_sync = function(self, payload, opts)
        -- Mock successful response
        return { body = '{"choices":[{"message":{"content":"Mocked response"}}]}' }, nil
      end
      return client
    end

    -- Mock the adapter handler
    local adapters = require("codecompanion.adapters")
    local original_call_handler = adapters.call_handler
    adapters.call_handler = function(adapter, handler_name, response)
      if handler_name == "parse_chat" then
        return { content = "Mocked response", role = "assistant" }
      end
      return original_call_handler(adapter, handler_name, response)
    end

    local bg = Background.new()
    local messages = {
      { role = "user", content = "Hello" }
    }
    local response, err = bg:ask_sync(messages)

    _G.bg_result = {
      response = response,
      error = err,
      original_messages = bg.messages -- Should be unchanged
    }

    -- Restore original functions
    http.new = original_new
    adapters.call_handler = original_call_handler
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result.response, { content = "Mocked response", role = "assistant" })
  h.eq(result.error, nil)
  h.eq(result.original_messages, {}) -- Should remain empty
end

T["Background"]["ask_sync()"]["handles HTTP client errors"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    -- Mock the HTTP client to return an error
    local http = require("codecompanion.http")
    local original_new = http.new
    http.new = function(opts)
      local client = original_new(opts)
      client.send_sync = function(self, payload, opts)
        return nil, { message = "Connection failed", stderr = "Network error" }
      end
      return client
    end

    local bg = Background.new()
    local messages = {
      { role = "user", content = "Hello" }
    }
    local response, err = bg:ask_sync(messages)

    _G.bg_result = {
      response = response,
      error = err
    }

    -- Restore original function
    http.new = original_new
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result.response, nil)
  h.expect_truthy(result.error)
  h.eq(result.error.message, "Connection failed")
end

T["Background"]["ask_sync()"]["errors with non-HTTP adapter"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    local bg = Background.new()
    -- Force adapter type to be non-HTTP
    bg.adapter.type = "acp"

    local messages = {
      { role = "user", content = "Hello" }
    }
    local response, err = bg:ask_sync(messages)

    _G.bg_result = {
      response = response,
      error = err
    }
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result.response, nil)
  h.expect_truthy(result.error)
  h.expect_contains("ask_sync only supports HTTP adapters", result.error.message)
end

T["Background"]["ask_async()"] = new_set()

T["Background"]["ask_async()"]["requires on_done callback"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    local bg = Background.new()
    local messages = {
      { role = "user", content = "Hello" }
    }

    local success, err = pcall(function()
      bg:ask_async(messages, {}) -- Missing on_done callback
    end)

    _G.bg_result = {
      success = success,
      error = err
    }
  ]])

  local result = child.lua_get("_G.bg_result")
  h.is_false(result.success)
  h.expect_contains("on_done callback is required", result.error)
end

T["Background"]["ask_async()"]["works with provided messages and callbacks"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    -- Mock the HTTP client
    local http = require("codecompanion.http")
    local original_new = http.new
    http.new = function(opts)
      local client = original_new(opts)
      client.send = function(self, payload, opts)
        -- Simulate async response by calling on_done immediately
        if opts.on_done then
          opts.on_done({ body = '{"choices":[{"message":{"content":"Async response"}}]}' })
        end
        return {
          id = "test-handle",
          job = nil,
          cancel = function() end,
          status = function() return "success" end
        }
      end
      return client
    end

    local bg = Background.new()
    local messages = {
      { role = "user", content = "Hello async" }
    }

    local callback_called = false
    local callback_data = nil

    local handle = bg:ask_async(messages, {
      on_done = function(data)
        callback_called = true
        callback_data = data
      end,
      on_error = function(err)
        callback_called = true
        callback_data = { error = err }
      end
    })

    _G.bg_result = {
      handle_id = handle.id,
      callback_called = callback_called,
      callback_data = callback_data,
      original_messages = bg.messages -- Should be unchanged
    }

    -- Restore original function
    http.new = original_new
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result.handle_id, "test-handle")
  h.is_true(result.callback_called)
  h.expect_truthy(result.callback_data)
  h.eq(result.original_messages, {}) -- Should remain empty
end

T["Background"]["ask_async()"]["returns dummy handle for non-HTTP adapter"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    local bg = Background.new()
    -- Force adapter type to be non-HTTP
    bg.adapter.type = "acp"

    local messages = {
      { role = "user", content = "Hello" }
    }

    local error_called = false
    local error_data = nil

    local handle = bg:ask_async(messages, {
      on_done = function(data) end,
      on_error = function(err)
        error_called = true
        error_data = err
      end
    })

    _G.bg_result = {
      handle_id = handle.id,
      handle_status = handle.status(),
      error_called = error_called,
      error_data = error_data
    }
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result.handle_id, "")
  h.eq(result.handle_status, "error")
  h.is_true(result.error_called)
  h.expect_truthy(result.error_data)
  h.expect_contains("ask_async only supports HTTP adapters", result.error_data.message)
end

T["Background"]["Integration"] = new_set()

T["Background"]["Integration"]["chat_make_title catalog works with ask_sync"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    -- Mock the HTTP client and adapter handler for a realistic response
    local http = require("codecompanion.http")
    local original_new = http.new
    http.new = function(opts)
      local client = original_new(opts)
      client.send_sync = function(self, payload, opts)
        -- Mock a title generation response
        return { body = '{"choices":[{"message":{"content":"Generated Chat Title"}}]}' }, nil
      end
      return client
    end

    local adapters = require("codecompanion.adapters")
    local original_call_handler = adapters.call_handler
    adapters.call_handler = function(adapter, handler_name, response)
      if handler_name == "parse_chat" then
        return { content = "Generated Chat Title", role = "assistant" }
      end
      return original_call_handler(adapter, handler_name, response)
    end

    -- Create a background instance
    local bg = Background.new()

    -- Mock a chat object with some messages
    local mock_chat = {
      title = nil, -- No title yet
      messages = {
        { role = "user", content = "What's the weather like?" },
        { role = "assistant", content = "I'd be happy to help you with weather information!" }
      }
    }

    -- Load and test the chat_make_title catalog
    local chat_make_title = require("codecompanion.interactions.background.catalog.chat_make_title")
    local response, err = chat_make_title.request(bg, mock_chat)

    _G.bg_result = {
      response = response,
      error = err,
      chat_title = mock_chat.title
    }

    -- Restore original functions
    http.new = original_new
    adapters.call_handler = original_call_handler
  ]])

  local result = child.lua_get("_G.bg_result")
  -- The chat_make_title should return early if chat already has a title,
  -- but since our mock_chat.title is nil, it should proceed
  h.eq(result.error, nil)
end

T["Background"]["Integration"]["chat_make_title returns early if chat has title"] = function()
  child.lua([[
    local Background = require("codecompanion.interactions.background")
    local config_module = require("codecompanion.config")
    config_module.setup(config)

    local bg = Background.new()

    -- Mock a chat object that already has a title
    local mock_chat = {
      title = "Existing Title",
      messages = {
        { role = "user", content = "What's the weather like?" },
        { role = "assistant", content = "I'd be happy to help you with weather information!" }
      }
    }

    local chat_make_title = require("codecompanion.interactions.background.catalog.chat_make_title")
    local response, err = chat_make_title.request(bg, mock_chat)

    _G.bg_result = {
      response = response,
      error = err,
      chat_title = mock_chat.title
    }
  ]])

  local result = child.lua_get("_G.bg_result")
  h.eq(result.response, nil) -- Should return early
  h.eq(result.error, nil)
  h.eq(result.chat_title, "Existing Title") -- Title should remain unchanged
end

return T
