local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        -- Store originals for restoration
        _G.original_http = package.loaded["codecompanion.http"]
        _G.original_adapters = package.loaded["codecompanion.adapters"]

        -- Minimal mock adapter - just enough to not crash
        local mock_adapter = {
          methods = {
            tools = {
              fetch_webpage = {
                setup = function() end,
                callback = function(adapter, data)
                  -- Let the real tool handle the formatting
                  return { status = "success", text = data.html or "mock content", screenshot = 'https://mock.screen.shot', pageshot = 'https://mock.page.shot' }
                end
              }
            }
          }
        }

        package.loaded["codecompanion.adapters"] = {
          resolve = function() return mock_adapter end
        }

        -- Minimal HTTP mock - just return some data
        package.loaded["codecompanion.http"] = {
          new = function()
            return {
              request = function(_, __, handlers)
                vim.schedule(function()
                  handlers.callback(nil, { html = "Hello World content" })
                end)
              end
            }
          end
        }

        -- Minimal config
        local config = require("codecompanion.config")
        config.interactions.chat.tools.fetch_webpage = {
          callback = "interactions.chat.tools.builtin.fetch_webpage",
          opts = { adapter = "test_adapter" }
        }
        config.adapters.test_adapter = {}
      ]])
    end,
    post_case = function()
      child.lua([[
        -- Restore original modules
        package.loaded["codecompanion.http"] = _G.original_http
        package.loaded["codecompanion.adapters"] = _G.original_adapters
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["fetches webpage text successfully"] = function()
  child.lua([[
    local tool_call = {
      ["function"] = {
        name = "fetch_webpage",
        arguments = '{"url": "https://example.com", "content_format": "text"}'
      },
      id = "test_call_id",
      type = "function"
    }

    -- Execute with real tool
    tools:execute(chat, { tool_call })
    vim.wait(200) -- Give time for async operations
  ]])

  local messages = child.lua_get("chat.messages")
  local tool_message = vim.tbl_filter(function(msg)
    return msg.role == "tool"
  end, messages)[1]

  -- Match the actual output format
  h.expect_contains('<attachment url="https://example.com">', tool_message.content)
  h.expect_contains("Hello World content", tool_message.content)
  h.expect_contains("</attachment>", tool_message.content)
end
T["fetches webpage screenshot successfully"] = function()
  child.lua([[
    local tool_call = {
      ["function"] = {
        name = "fetch_webpage",
        arguments = '{"url": "https://example.com", "content_format": "screenshot"}'
      },
      id = "test_call_id",
      type = "function"
    }

    -- Execute with real tool
    tools:execute(chat, { tool_call })
    vim.wait(200) -- Give time for async operations
  ]])

  local messages = child.lua_get("chat.messages")
  local tool_message = vim.tbl_filter(function(msg)
    return msg.role == "tool"
  end, messages)[1]

  -- Match the actual output format
  h.expect_contains(
    '<attachment image_url="https://mock.screen.shot">Screenshot of https://example.com</attachment>',
    tool_message.content
  )
end

T["fetches webpage pageshot successfully"] = function()
  child.lua([[
    local tool_call = {
      ["function"] = {
        name = "fetch_webpage",
        arguments = '{"url": "https://example.com", "content_format": "pageshot"}'
      },
      id = "test_call_id",
      type = "function"
    }

    -- Execute with real tool
    tools:execute(chat, { tool_call })
    vim.wait(200) -- Give time for async operations
  ]])

  local messages = child.lua_get("chat.messages")
  local tool_message = vim.tbl_filter(function(msg)
    return msg.role == "tool"
  end, messages)[1]

  -- Match the actual output format
  h.expect_contains(
    '<attachment image_url="https://mock.page.shot">Pageshot of https://example.com</attachment>',
    tool_message.content
  )
end
return T
