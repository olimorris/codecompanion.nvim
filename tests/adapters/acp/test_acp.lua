local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        h.setup_plugin()
        package.loaded["codecompanion.config"] = require("tests.config")
      ]])
    end,
    post_case = child.stop,
  },
})

T["ACP Adapter"] = new_set()

T["ACP Adapter"]["can resolve ACP adapter by type"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").resolve("test_acp")
    return {
      name = adapter.name,
      type = adapter.type,
      resolved = require("codecompanion.adapters").resolved(adapter)
    }
  ]])

  h.eq({
    name = "test_acp",
    type = "acp",
    resolved = true,
  }, result)
end

T["ACP Adapter"]["handles missing adapter gracefully"] = function()
  local result = child.lua([[
    -- Try to resolve a non-existent ACP adapter
    local adapter = require("codecompanion.adapters.acp").resolve("non_existent_adapter")
    return { adapter_is_nil = adapter == nil }
  ]])

  h.eq(true, result.adapter_is_nil)
end

T["ACP Adapter"]["can make adapter safe for serialization"] = function()
  local result = child.lua([[
    local adapter_config = {
      name = "test_acp",
      formatted_name = "Test ACP Adapter",
      type = "acp", command = { "node", "agent.js" },
      defaults = { model = "test-model" },
      parameters = { temperature = 0.7 },
      handlers = {
        setup = function() return true end,
        teardown = function() end
      }
    }

    local adapter = require("codecompanion.adapters.acp").new(adapter_config)
    local output = require("codecompanion.adapters").make_safe(adapter)

    -- Return a simplified version for testing as we can't pass functions through child processes
    return {
      name = output.name,
      type = output.type,
      command = output.command,
      defaults = output.defaults,
      params = output.params,
    }
  ]])

  h.eq("test_acp", result.name)
  h.eq("acp", result.type)
  h.eq({ "node", "agent.js" }, result.command)
end

T["ACP Adapter"]["extends adapters correctly"] = function()
  local result = child.lua([[
    -- Create base config as a function (like real adapters)
    local base_config = function()
      return {
        name = "base_acp",
        type = "acp",
        command = { "node", "base-agent.js" },
        defaults = { model = "base-model" }
      }
    end

    local extended = require("codecompanion.adapters").extend(base_config, {
      defaults = { temperature = 0.8 },
      parameters = { max_tokens = 1000 }
    })

    return {
      name = extended.name,
      defaults = extended.defaults,
      parameters = extended.parameters
    }
  ]])

  h.eq("base_acp", result.name)
  h.eq({ model = "base-model", temperature = 0.8 }, result.defaults)
  h.eq({ max_tokens = 1000 }, result.parameters)
end

T["ACP Connection"] = new_set()

T["ACP Connection"]["can_close_session follows the advertised close capability"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")
    local with_close = setmetatable({
      _agent_info = { agentCapabilities = { sessionCapabilities = { close = {} } } },
    }, { __index = Connection })
    local without_close = setmetatable({
      _agent_info = { agentCapabilities = { sessionCapabilities = {} } },
    }, { __index = Connection })
    local null_close = setmetatable({
      _agent_info = { agentCapabilities = { sessionCapabilities = { close = vim.NIL } } },
    }, { __index = Connection })
    local without_agent_info = setmetatable({}, { __index = Connection })

    return {
      with_close = with_close:can_close_session(),
      without_close = without_close:can_close_session(),
      null_close = null_close:can_close_session(),
      without_agent_info = without_agent_info:can_close_session(),
    }
  ]])

  h.eq(true, result.with_close)
  h.eq(false, result.without_close)
  h.eq(false, result.null_close)
  h.eq(false, result.without_agent_info)
end

T["ACP Connection"]["disconnect closes the session before killing a capable agent"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")
    local events = {}
    local connection = setmetatable({
      session_id = "ses_test",
      _agent_info = { agentCapabilities = { sessionCapabilities = { close = {} } } },
      _initialized = true,
      _authenticated = true,
      _state = {
        handle = { kill = function(_, signal) table.insert(events, "kill:" .. signal) end },
      },
      send_rpc_request = function(_, request)
        table.insert(events, request.method .. ":" .. request.timeout)
        return {}
      end,
    }, { __index = Connection })

    connection:disconnect()
    return events
  ]])

  h.eq({ "session/close:2000", "kill:sigterm" }, result)
end

T["ACP Connection"]["disconnect skips session/close when the agent doesn't advertise it"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")
    local events = {}
    local connection = setmetatable({
      session_id = "ses_test",
      _agent_info = { agentCapabilities = { sessionCapabilities = {} } },
      _initialized = true,
      _authenticated = true,
      _state = {
        handle = { kill = function(_, signal) table.insert(events, "kill:" .. signal) end },
      },
      send_rpc_request = function(_, request)
        table.insert(events, request.method)
        return {}
      end,
    }, { __index = Connection })

    connection:disconnect()
    return events
  ]])

  h.eq({ "kill:sigterm" }, result)
end

T["ACP Connection"]["disconnect still kills the process when session/close fails"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")
    local events = {}
    local connection = setmetatable({
      session_id = "ses_test",
      _agent_info = { agentCapabilities = { sessionCapabilities = { close = {} } } },
      _initialized = true,
      _authenticated = true,
      _state = {
        handle = { kill = function(_, signal) table.insert(events, "kill:" .. signal) end },
      },
      send_rpc_request = function()
        error("agent hung up")
      end,
    }, { __index = Connection })

    connection:disconnect()
    return events
  ]])

  h.eq({ "kill:sigterm" }, result)
end

return T
