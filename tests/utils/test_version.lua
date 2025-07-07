local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        version = require("codecompanion.utils.version")
      ]])
    end,
    post_once = function()
      child.stop()
    end,
  },
})

T["get_version"] = new_set({
  hooks = {
    pre_case = function()
      -- Mock io.popen for testing
      child.lua([[
        _G.original_io_popen = io.popen
        _G.mock_git_result = nil
        _G.mock_git_error = false
        
        io.popen = function(cmd)
          if _G.mock_git_error then
            return nil
          end
          
          local handle = {
            read = function(self, format)
              return _G.mock_git_result or ""
            end,
            close = function(self)
              return true
            end
          }
          return handle
        end
      ]])
    end,
    post_case = function()
      -- Restore original io.popen
      child.lua([[
        io.popen = _G.original_io_popen
      ]])
    end,
  },
})

T["get_version"]["returns version from git describe"] = function()
  child.lua([[
    _G.mock_git_result = "v1.2.3-4-g1234567"
  ]])

  local version = child.lua_get("version.get_version()")
  h.eq(version, "v1.2.3-4-g1234567")
end

T["get_version"]["strips whitespace from git result"] = function()
  child.lua([[
    _G.mock_git_result = "v1.2.3-dirty\n"
  ]])

  local version = child.lua_get("version.get_version()")
  h.eq(version, "v1.2.3-dirty")
end

T["get_version"]["returns unknown when git command fails"] = function()
  child.lua([[
    _G.mock_git_error = true
  ]])

  local version = child.lua_get("version.get_version()")
  h.eq(version, "unknown")
end

T["get_version"]["returns unknown when git result is empty"] = function()
  child.lua([[
    _G.mock_git_result = ""
  ]])

  local version = child.lua_get("version.get_version()")
  h.eq(version, "unknown")
end

T["get_version"]["returns unknown when plugin path cannot be determined"] = function()
  child.lua([[
    -- Mock debug.getinfo to return nil
    _G.original_debug_getinfo = debug.getinfo
    debug.getinfo = function(level, what)
      return { source = "@" }
    end
  ]])

  local version = child.lua_get("version.get_version()")
  h.eq(version, "unknown")

  child.lua([[
    debug.getinfo = _G.original_debug_getinfo
  ]])
end

T["get_user_agent"] = new_set({
  hooks = {
    pre_case = function()
      -- Use the same io.popen mocking
      child.lua([[
        _G.original_io_popen = io.popen
        _G.mock_git_result = nil
        _G.mock_git_error = false
        
        io.popen = function(cmd)
          if _G.mock_git_error then
            return nil
          end
          
          local handle = {
            read = function(self, format)
              return _G.mock_git_result or ""
            end,
            close = function(self)
              return true
            end
          }
          return handle
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        io.popen = _G.original_io_popen
      ]])
    end,
  },
})

T["get_user_agent"]["returns CodeCompanion with version"] = function()
  child.lua([[
    _G.mock_git_result = "v1.2.3"
  ]])

  local user_agent = child.lua_get("version.get_user_agent()")
  h.eq(user_agent, "CodeCompanion/1.2.3")
end

T["get_user_agent"]["removes v prefix from version"] = function()
  child.lua([[
    _G.mock_git_result = "v17.6.0-1-g1234567"
  ]])

  local user_agent = child.lua_get("version.get_user_agent()")
  h.eq(user_agent, "CodeCompanion/17.6.0-1-g1234567")
end

T["get_user_agent"]["returns CodeCompanion when version is unknown"] = function()
  child.lua([[
    _G.mock_git_error = true
  ]])

  local user_agent = child.lua_get("version.get_user_agent()")
  h.eq(user_agent, "CodeCompanion")
end

T["get_user_agent"]["handles version without v prefix"] = function()
  child.lua([[
    _G.mock_git_result = "1.2.3-dirty"
  ]])

  local user_agent = child.lua_get("version.get_user_agent()")
  h.eq(user_agent, "CodeCompanion/1.2.3-dirty")
end

T["get_user_agent"]["does not contain newlines"] = function()
  child.lua([[
    _G.mock_git_result = "v1.2.3\n"
  ]])

  local user_agent = child.lua_get("version.get_user_agent()")
  h.eq(user_agent, "CodeCompanion/1.2.3")
  h.eq(user_agent:find("\n"), nil)
end

return T
