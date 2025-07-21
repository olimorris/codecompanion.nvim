local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

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
                  return { status = "success", content = data.html or "mock content" }
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
        config.strategies.chat.tools.fetch_webpage = {
          callback = "strategies.chat.agents.tools.fetch_webpage",
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

T["fetches webpage content successfully"] = function()
  child.lua([[
    local tool_call = {
      ["function"] = {
        name = "fetch_webpage",
        arguments = '{"url": "https://example.com"}'
      },
      id = "test_call_id",
      type = "function"
    }

    -- Execute the real agent with real tool
    agent:execute(chat, { tool_call })
    vim.wait(500) -- Give time for async operations
  ]])

  local messages = child.lua_get("chat.messages")
  local tool_message = vim.tbl_filter(function(msg)
    return msg.role == "tool"
  end, messages)[1]

  -- Match the actual output format
  h.expect_contains('<fetchWebpageTool url="https://example.com">', tool_message.content)
  h.expect_contains("Hello World content", tool_message.content)
  h.expect_contains("</fetchWebpageTool>", tool_message.content)
end

return T
