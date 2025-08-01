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
    --require("tests.log")
    --local log = require("codecompanion.utils.log")

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

-- T["ACP Adapter"]["can resolve an adapter when the type is specified"] = function()
--   local result = child.lua([[
--     --require("tests.log")
--     --local log = require("codecompanion.utils.log")
--
--     local adapter = require("codecompanion.adapters").resolve("acp.test_acp")
--
--     return {
--       name = adapter.name,
--       type = adapter.type,
--       resolved = require("codecompanion.adapters").resolved(adapter)
--     }
--   ]])
--
--   h.eq({
--     name = "test_acp",
--     type = "acp",
--     resolved = true,
--   }, result)
-- end

T["ACP Adapter"]["handles missing adapter gracefully"] = function()
  local result = child.lua([[
    -- Try to resolve a non-existent ACP adapter
    local ok, err = pcall(function()
      return require("codecompanion.adapters.acp").resolve("non_existent_adapter")
    end)
    return { ok = ok, has_error = err ~= nil }
  ]])

  h.eq(false, result.ok)
end

T["ACP Adapter"]["can make adapter safe for serialization"] = function()
  local result = child.lua([[
    local adapter_config = {
      name = "test_acp",
      formatted_name = "Test ACP Adapter",
      type = "acp",
      command = { "node", "agent.js" },
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

return T
