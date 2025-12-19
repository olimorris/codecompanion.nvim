local h = require("tests.helpers")
local slash_command_filter = require("codecompanion.interactions.chat.slash_commands.filter")

local new_set = MiniTest.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      -- Clear cache before each test
      slash_command_filter.refresh_cache()
    end,
  },
})

T["filters out disabled slash commands"] = function()
  local slash_commands_config = {
    enabled_cmd = {
      description = "test",
      enabled = true,
    },
    disabled_cmd = {
      description = "test",
      enabled = false,
    },
    function_disabled_cmd = {
      description = "test",
      enabled = function()
        return false
      end,
    },
    default_enabled_cmd = {
      description = "test",
      -- No enabled field means enabled by default
    },
    opts = {},
  }

  local filtered = slash_command_filter.filter_enabled_slash_commands(slash_commands_config)

  h.eq(filtered.enabled_cmd ~= nil, true)
  h.eq(filtered.default_enabled_cmd ~= nil, true)
  h.eq(filtered.disabled_cmd, nil)
  h.eq(filtered.function_disabled_cmd, nil)
  h.eq(filtered.opts ~= nil, true) -- opts should remain
end

T["respects adapter context in enabled function"] = function()
  local slash_commands_config = {
    adapter_specific_cmd = {
      description = "test",
      enabled = function(opts)
        return opts.adapter and opts.adapter.name == "copilot"
      end,
    },
  }

  local copilot_adapter = { name = "copilot" }
  local openai_adapter = { name = "openai" }

  local filtered_copilot =
    slash_command_filter.filter_enabled_slash_commands(slash_commands_config, { adapter = copilot_adapter })

  slash_command_filter.refresh_cache()

  local filtered_openai =
    slash_command_filter.filter_enabled_slash_commands(slash_commands_config, { adapter = openai_adapter })

  h.eq(filtered_copilot.adapter_specific_cmd ~= nil, true)
  h.eq(filtered_openai.adapter_specific_cmd, nil)
end

T["cache invalidation"] = new_set()

T["cache invalidation"]["detects config changes when commands are added"] = function()
  local initial_config = {
    cmd1 = { description = "test", enabled = true },
    opts = {},
  }

  -- First call - should cache
  local filtered1 = slash_command_filter.filter_enabled_slash_commands(initial_config)
  h.eq(filtered1.cmd1 ~= nil, true)
  h.eq(filtered1.cmd2, nil)

  -- Add a new command to the config
  initial_config.cmd2 = { description = "test", enabled = true }

  -- Second call - should detect config change and return new command
  local filtered2 = slash_command_filter.filter_enabled_slash_commands(initial_config)
  h.eq(filtered2.cmd1 ~= nil, true)
  h.eq(filtered2.cmd2 ~= nil, true)
end

T["cache invalidation"]["detects config changes when commands are removed"] = function()
  local config = {
    cmd1 = { description = "test", enabled = true },
    cmd2 = { description = "test", enabled = true },
    opts = {},
  }

  -- First call - should cache both commands
  local filtered1 = slash_command_filter.filter_enabled_slash_commands(config)
  h.eq(filtered1.cmd1 ~= nil, true)
  h.eq(filtered1.cmd2 ~= nil, true)

  -- Remove a command from the config
  config.cmd2 = nil

  -- Second call - should detect config change and return only remaining command
  local filtered2 = slash_command_filter.filter_enabled_slash_commands(config)
  h.eq(filtered2.cmd1 ~= nil, true)
  h.eq(filtered2.cmd2, nil)
end

return T
