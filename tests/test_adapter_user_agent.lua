local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        config = require("codecompanion.config")
        Adapter = require("codecompanion.adapters.init")
        version = require("codecompanion.utils.version")
        
        -- Mock version module
        _G.original_get_user_agent = version.get_user_agent
        version.get_user_agent = function()
          return "CodeCompanion/1.2.3"
        end
      ]])
    end,
    post_once = function()
      child.stop()
    end,
  },
})

T["User-Agent header"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        -- Reset config to default state
        config.adapters = {
          opts = {}
        }
      ]])
    end,
    post_case = function()
      child.lua([[
        -- Restore original function
        version.get_user_agent = _G.original_get_user_agent
      ]])
    end,
  },
})

T["User-Agent header"]["is added by default"] = function()
  child.lua([[
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  h.eq(user_agent, "CodeCompanion/1.2.3")
end

T["User-Agent header"]["can be disabled"] = function()
  child.lua([[
    config.adapters.opts.add_user_agent = false
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  h.eq(user_agent, vim.NIL)
end

T["User-Agent header"]["merges with existing headers"] = function()
  child.lua([[
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
      headers = {
        ["Authorization"] = "Bearer token123",
        ["Content-Type"] = "application/json",
      }
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  local auth = child.lua_get("test_adapter.headers['Authorization']")
  local content_type = child.lua_get("test_adapter.headers['Content-Type']")

  h.eq(user_agent, "CodeCompanion/1.2.3")
  h.eq(auth, "Bearer token123")
  h.eq(content_type, "application/json")
end

T["User-Agent header"]["adapter headers take precedence"] = function()
  child.lua([[
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
      headers = {
        ["User-Agent"] = "CustomAgent/1.0",
      }
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  h.eq(user_agent, "CustomAgent/1.0")
end

T["User-Agent header"]["merges with custom default headers"] = function()
  child.lua([[
    config.adapters.opts.default_headers = {
      ["X-Custom-Header"] = "custom-value",
      ["Authorization"] = "Bearer default-token",
    }
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
      headers = {
        ["Authorization"] = "Bearer override-token",
      }
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  local custom_header = child.lua_get("test_adapter.headers['X-Custom-Header']")
  local auth = child.lua_get("test_adapter.headers['Authorization']")

  h.eq(user_agent, "CodeCompanion/1.2.3")
  h.eq(custom_header, "custom-value")
  h.eq(auth, "Bearer override-token")
end

T["User-Agent header"]["works with no custom headers"] = function()
  child.lua([[
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  h.eq(user_agent, "CodeCompanion/1.2.3")
end

T["User-Agent header"]["handles unknown version"] = function()
  child.lua([[
    version.get_user_agent = function()
      return "CodeCompanion"
    end
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  h.eq(user_agent, "CodeCompanion")
end

T["User-Agent header"]["does not contain newlines"] = function()
  child.lua([[
    version.get_user_agent = function()
      return "CodeCompanion/1.2.3-dirty"
    end
    test_adapter = Adapter.new({
      name = "test",
      url = "https://example.com",
    })
  ]])

  local user_agent = child.lua_get("test_adapter.headers['User-Agent']")
  h.eq(user_agent:find("\n"), nil)
  h.eq(user_agent:find("\r"), nil)
end

return T
