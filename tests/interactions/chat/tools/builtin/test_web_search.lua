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
              web_search = {
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
        config.interactions.chat.tools.web_search = {
          path = "interactions.chat.tools.builtin.web_search",
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

T["rejects a null query"] = function()
  child.lua([[
    local tool_call = {
      ["function"] = {
        name = "web_search",
        arguments = '{"query": null, "domains": null}'
      },
      id = "test_call_id",
      type = "function"
    }

    tools:execute(chat, { tool_call })
  ]])

  local messages = child.lua_get("chat.messages")
  local tool_message = vim.tbl_filter(function(message)
    return message.role == "tool"
  end, messages)[1]

  h.expect_contains("No query provided for the web_search tool", tool_message.content)
end

T["searches across all domains when domains is an empty string"] = function()
  child.lua([[
    package.loaded["codecompanion.http"].new = function()
      return {
        request = function(_, payload, handlers)
          _G.request_called = true
          _G.request_domains = payload.domains
          vim.schedule(function()
            handlers.callback(nil, { results = {} })
          end)
        end,
      }
    end

    tools:execute(chat, { {
      ["function"] = { name = "web_search", arguments = '{"query":"neovim plugins","domains":""}' },
      id = "test_call_id",
      type = "function",
    } })
    vim.wait(200)
  ]])

  h.eq(true, child.lua_get("_G.request_called"))
  h.eq(true, child.lua_get("_G.request_domains == nil"))
  h.eq(1, #vim.tbl_filter(function(message)
    return message.role == "tool"
  end, child.lua_get("chat.messages")))
end

T["searches across all domains when domains is null"] = function()
  child.lua([[
    package.loaded["codecompanion.http"].new = function()
      return {
        request = function(_, payload, handlers)
          _G.request_called = true
          _G.request_domains = payload.domains
          vim.schedule(function()
            handlers.callback(nil, { results = {} })
          end)
        end,
      }
    end

    tools:execute(chat, { {
      ["function"] = { name = "web_search", arguments = '{"query":"neovim plugins","domains":null}' },
      id = "test_call_id",
      type = "function",
    } })
    assert(vim.wait(2000, function()
      return vim.iter(chat.messages):any(function(message) return message.role == "tool" end)
    end))
  ]])

  h.eq(true, child.lua_get("_G.request_called"))
  h.eq(true, child.lua_get("_G.request_domains == nil"))
end

T["rejects invalid domains and reports the reason to the LLM"] = function()
  child.lua([[
    tools:execute(chat, { {
      ["function"] = { name = "web_search", arguments = '{"query":"neovim plugins","domains":[null]}' },
      id = "test_call_id",
      type = "function",
    } })
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("domains must be an array of strings", output)
end

T["searches web successfully"] = function()
  child.lua([[
    local tool_call = {
      ["function"] = {
        name = "web_search",
        arguments = '{"query": "neovim plugins", "domains": []}'
      },
      id = "test_call_id",
      type = "function"
    }

    -- Execute the real tool
    tools:execute(chat, { tool_call })
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
