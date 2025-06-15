local ToolFilter = require("codecompanion.strategies.chat.agents.tool_filter")
local h = require("tests.helpers")

local new_set = MiniTest.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      -- Clear cache before each test
      ToolFilter.refresh_cache()
    end,
  },
})

T["filters out disabled tools"] = function()
  local tools_config = {
    enabled_tool = {
      callback = "test",
      enabled = true,
    },
    disabled_tool = {
      callback = "test",
      enabled = false,
    },
    function_disabled_tool = {
      callback = "test",
      enabled = function()
        return false
      end,
    },
    default_enabled_tool = {
      callback = "test",
      -- No enabled field means enabled by default
    },
    opts = {},
  }

  local filtered = ToolFilter.filter_enabled_tools(tools_config)

  h.eq(filtered.enabled_tool ~= nil, true)
  h.eq(filtered.default_enabled_tool ~= nil, true)
  h.eq(filtered.disabled_tool, nil)
  h.eq(filtered.function_disabled_tool, nil)
  h.eq(filtered.opts ~= nil, true) -- opts should remain
end

T["filters disabled tools in groups"] = function()
  local tools_config = {
    tool1 = { callback = "test", enabled = true },
    tool2 = { callback = "test", enabled = false },
    tool3 = { callback = "test", enabled = true },
    groups = {
      mixed_group = {
        tools = { "tool1", "tool2", "tool3" },
      },
      empty_group = {
        tools = { "tool2" }, -- Only disabled tool
      },
    },
    opts = {},
  }

  local filtered = ToolFilter.filter_enabled_tools(tools_config)

  h.eq(#filtered.groups.mixed_group.tools, 2) -- Only tool1 and tool3
  h.eq(filtered.groups.empty_group, nil) -- Empty group should be removed
end

return T
