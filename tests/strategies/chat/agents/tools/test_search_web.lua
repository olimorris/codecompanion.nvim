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
              search_web = {
                setup = function() end,
                callback = function(adapter, data)
                  -- Let the real tool handle the formatting
                  return { status = "success", content = data.results or {} }
                end
              }
            }
          }
        }

        package.loaded["codecompanion.adapters"] = {
          resolve = function() return mock_adapter end
        }

        -- Minimal HTTP mock - just return some search results
        package.loaded["codecompanion.http"] = {
          new = function()
            return {
              request = function(_, __, handlers)
                vim.schedule(function()
                  handlers.callback(nil, {
                    results = {
                      {
                        url = "https://example.com/result1",
                        title = "Example Result 1",
                        content = "Content of first search result"
                      },
                      {
                        url = "https://example.com/result2",
                        title = "Example Result 2",
                        content = "Content of second search result"
                      }
                    }
                  })
                end)
              end
            }
          end
        }

        -- Minimal config
        local config = require("codecompanion.config")
        config.strategies.chat.tools.search_web = {
          callback = "strategies.chat.agents.tools.search_web",
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

T["searches web successfully"] = function()
  child.lua([[
    local tool_call = {
      ["function"] = {
        name = "search_web",
        arguments = '{"query": "neovim plugins", "domains": []}'
      },
      id = "test_call_id",
      type = "function"
    }

    -- Execute the real agent with real tool
    agent:execute(chat, { tool_call })
    vim.wait(200) -- Give time for async operations
  ]])

  local messages = child.lua_get("chat.messages")
  local tool_message = vim.tbl_filter(function(msg)
    return msg.role == "tool"
  end, messages)[1]

  -- Match the actual output format
  h.expect_contains('<attachment url="https://example.com/result1" title="Example Result 1">', tool_message.content)
  h.expect_contains("Content of first search result", tool_message.content)
  h.expect_contains("</attachment>", tool_message.content)
end

return T
