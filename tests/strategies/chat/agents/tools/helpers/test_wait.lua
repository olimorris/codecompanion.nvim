local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        wait = require('codecompanion.strategies.chat.agents.tools.helpers.wait')
        utils = require('codecompanion.utils')

        -- Mock utils.notify to avoid actual notifications in tests
        utils.notify = function(msg)
          _G.last_notify = msg
        end

        -- Helper to capture callback results
        _G.callback_results = {}
        _G.test_callback = function(result)
          table.insert(_G.callback_results, result)
        end

        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.callback_results = {}
        _G.last_notify = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["for_decision()"] = new_set()

T["for_decision()"]["auto-approves when auto_tool_mode is enabled"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = true
    wait.for_decision("test_id", {"Accept", "Reject"}, _G.test_callback)
  ]])

  local results = child.lua_get("_G.callback_results")
  h.eq(#results, 1)
  h.eq(results[1].accepted, true)
end

T["for_decision()"]["waits for matching event with correct id"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false
    wait.for_decision("test_123", {"CodeCompanionAccept", "CodeCompanionReject"}, _G.test_callback)
  ]])

  -- Trigger the accept event with matching ID
  child.lua([[
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeCompanionAccept",
      data = { id = "test_123" }
    })
  ]])

  local results = child.lua_get("_G.callback_results")
  h.eq(#results, 1)
  h.eq(results[1].accepted, true)
  h.eq(results[1].event, "CodeCompanionAccept")
end

T["for_decision()"]["waits for reject event with correct id"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false
    wait.for_decision("test_456", {"CodeCompanionAccept", "CodeCompanionReject"}, _G.test_callback)
  ]])

  -- Trigger the reject event with matching ID
  child.lua([[
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeCompanionReject",
      data = { id = "test_456" }
    })
  ]])

  local results = child.lua_get("_G.callback_results")
  h.eq(#results, 1)
  h.eq(results[1].accepted, false)
  h.eq(results[1].event, "CodeCompanionReject")
end

T["for_decision()"]["ignores events with wrong id"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false
    wait.for_decision("test_789", {"CodeCompanionAccept", "CodeCompanionReject"}, _G.test_callback)
  ]])

  -- Trigger event with wrong ID - should be ignored
  child.lua([[
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeCompanionAccept",
      data = { id = "wrong_id" }
    })
  ]])

  -- Should have no callback results yet
  local results = child.lua_get("_G.callback_results")
  h.eq(#results, 0)

  -- Now trigger with correct ID
  child.lua([[
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeCompanionAccept",
      data = { id = "test_789" }
    })
  ]])

  results = child.lua_get("_G.callback_results")
  h.eq(#results, 1)
  h.eq(results[1].accepted, true)
end

T["for_decision()"]["handles notification option"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false
    wait.for_decision("test_notify", {"Accept", "Reject"}, _G.test_callback, {
      notify = "Please make a decision..."
    })
  ]])

  local notify_msg = child.lua_get("_G.last_notify")
  h.eq(notify_msg, "Please make a decision...")
end

T["for_decision()"]["times out after specified duration"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false
    wait.for_decision("test_timeout", {"Accept", "Reject"}, _G.test_callback, {
      timeout = 100  -- Very short timeout for testing
    })
  ]])

  -- Wait for timeout to occur
  child.lua("vim.wait(200, function() return #_G.callback_results > 0 end)")

  local results = child.lua_get("_G.callback_results")
  h.eq(#results, 1)
  h.eq(results[1].accepted, false)
  h.eq(results[1].timeout, true)
end

T["for_decision()"]["cleans up autocmds after decision"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false
    wait.for_decision("test_cleanup", {"Accept", "Reject"}, _G.test_callback)
  ]])

  -- Check that autocommand group was created
  local augroups_before = child.lua([[
    local groups = {}
    for _, group in ipairs(vim.api.nvim_get_autocmds({})) do
      if group.group_name and group.group_name:match("codecompanion.agent.tools.wait_") then
        table.insert(groups, group.group_name)
      end
    end
    return groups
  ]])

  -- Trigger accept event
  child.lua([[
    vim.api.nvim_exec_autocmds("User", {
      pattern = "Accept",
      data = { id = "test_cleanup" }
    })
  ]])

  -- Check that autocommand group was cleaned up
  local augroups_after = child.lua([[
    local groups = {}
    for _, group in ipairs(vim.api.nvim_get_autocmds({})) do
      if group.group_name and group.group_name:match("codecompanion.agent.tools.wait_") then
        table.insert(groups, group.group_name)
      end
    end
    return groups
  ]])

  -- Should have fewer autocommands after cleanup
  expect.no_equality(#augroups_before, 0) -- Had autocommands before
  h.eq(#augroups_after, 0) -- No autocommands after
end

T["for_decision()"]["passes event data to callback"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false
    wait.for_decision("test_data", {"Accept", "Reject"}, _G.test_callback)
  ]])

  -- Trigger event with custom data
  child.lua([[
    vim.api.nvim_exec_autocmds("User", {
      pattern = "Accept",
      data = {
        id = "test_data",
        custom_field = "test_value",
        number_field = 42
      }
    })
  ]])

  local results = child.lua_get("_G.callback_results")
  h.eq(#results, 1)
  h.eq(results[1].accepted, true)
  h.eq(results[1].data.custom_field, "test_value")
  h.eq(results[1].data.number_field, 42)
end

T["for_decision()"]["uses default timeout from config"] = function()
  child.lua([[
    vim.g.codecompanion_auto_tool_mode = false

    -- Reload wait module to pick up mocked config
    package.loaded["codecompanion.strategies.chat.agents.tools.helpers.wait"] = nil
    wait = require('codecompanion.strategies.chat.agents.tools.helpers.wait')

    -- Start timer to track roughly when timeout occurs
    _G.start_time = vim.loop.hrtime()
    wait.for_decision("test_default_timeout", {"Accept", "Reject"}, function(result)
      _G.timeout_duration = (vim.loop.hrtime() - _G.start_time) / 1000000 -- Convert to ms
      _G.test_callback(result)
    end)
  ]])

  -- Wait for timeout with some buffer
  child.lua("vim.wait(3000, function() return #_G.callback_results > 0 end)")

  local results = child.lua_get("_G.callback_results")
  local duration = child.lua_get("_G.timeout_duration")

  h.eq(#results, 1)
  h.eq(results[1].timeout, true)
  expect.no_equality(duration, nil)
end

return T
