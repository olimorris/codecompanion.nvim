local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
      ]])
    end,
    post_case = function()
      child.lua([[
        -- Clear all commands after each test
        local commands = require("codecompanion.interactions.chat.acp.commands")
        commands.clear_all()
      ]])
    end,
    post_once = child.stop,
  },
})

T["ACPCommands"] = new_set()

T["ACPCommands"]["registers commands for a session"] = function()
  local result = child.lua([[
    local commands = require("codecompanion.interactions.chat.acp.commands")

    local test_commands = {
      { name = "cost", description = "Show token costs", input = nil },
      { name = "context", description = "Manage context", input = { hint = "[options]" } },
    }

    commands.register_commands("session-123", test_commands)

    local retrieved = commands.get_commands_for_session("session-123")

    return {
      count = #retrieved,
      first_name = retrieved[1].name,
      first_desc = retrieved[1].description,
      second_has_input = retrieved[2].input ~= nil,
      second_hint = retrieved[2].input and retrieved[2].input.hint or nil,
    }
  ]])

  h.eq(2, result.count)
  h.eq("cost", result.first_name)
  h.eq("Show token costs", result.first_desc)
  h.is_true(result.second_has_input)
  h.eq("[options]", result.second_hint)
end

T["ACPCommands"]["links buffer to session"] = function()
  local result = child.lua([[
    local commands = require("codecompanion.interactions.chat.acp.commands")

    local test_commands = {
      { name = "cost", description = "Show costs" },
    }

    commands.register_commands("session-456", test_commands)

    -- Create a buffer and link it
    local bufnr = vim.api.nvim_create_buf(false, true)
    commands.link_buffer_to_session(bufnr, "session-456")

    local retrieved = commands.get_commands_for_buffer(bufnr)

    return {
      count = #retrieved,
      command_name = retrieved[1] and retrieved[1].name or nil,
    }
  ]])

  h.eq(1, result.count)
  h.eq("cost", result.command_name)
end

T["ACPCommands"]["returns empty array for unknown session"] = function()
  local result = child.lua([[
    local commands = require("codecompanion.interactions.chat.acp.commands")

    local retrieved = commands.get_commands_for_session("nonexistent-session")

    return {
      count = #retrieved,
    }
  ]])

  h.eq(0, result.count)
end

T["ACPCommands"]["returns empty array for unlinked buffer"] = function()
  local result = child.lua([[
    local commands = require("codecompanion.interactions.chat.acp.commands")

    local bufnr = vim.api.nvim_create_buf(false, true)
    local retrieved = commands.get_commands_for_buffer(bufnr)

    return {
      count = #retrieved,
    }
  ]])

  h.eq(0, result.count)
end

T["ACPCommands"]["clears session commands"] = function()
  local result = child.lua([[
    local commands = require("codecompanion.interactions.chat.acp.commands")

    commands.register_commands("session-789", {
      { name = "test", description = "Test" },
    })

    local before = #commands.get_commands_for_session("session-789")

    commands.clear_session("session-789")

    local after = #commands.get_commands_for_session("session-789")

    return {
      before = before,
      after = after,
    }
  ]])

  h.eq(1, result.before)
  h.eq(0, result.after)
end

T["ACPCommands"]["unlinks buffer"] = function()
  local result = child.lua([[
    local commands = require("codecompanion.interactions.chat.acp.commands")

    commands.register_commands("session-abc", {
      { name = "test", description = "Test" },
    })

    local bufnr = vim.api.nvim_create_buf(false, true)
    commands.link_buffer_to_session(bufnr, "session-abc")

    local before = #commands.get_commands_for_buffer(bufnr)

    commands.unlink_buffer(bufnr)

    local after = #commands.get_commands_for_buffer(bufnr)

    return {
      before = before,
      after = after,
    }
  ]])

  h.eq(1, result.before)
  h.eq(0, result.after)
end

T["ACPCommands"]["handles multiple sessions"] = function()
  local result = child.lua([[
    local commands = require("codecompanion.interactions.chat.acp.commands")

    commands.register_commands("session-1", {
      { name = "cost", description = "Cost for session 1" },
    })

    commands.register_commands("session-2", {
      { name = "context", description = "Context for session 2" },
      { name = "cost", description = "Cost for session 2" },
    })

    local session1_cmds = commands.get_commands_for_session("session-1")
    local session2_cmds = commands.get_commands_for_session("session-2")

    return {
      session1_count = #session1_cmds,
      session2_count = #session2_cmds,
      session1_cmd = session1_cmds[1].name,
      session2_cmd = session2_cmds[1].name,
    }
  ]])

  h.eq(1, result.session1_count)
  h.eq(2, result.session2_count)
  h.eq("cost", result.session1_cmd)
  h.eq("context", result.session2_cmd)
end

return T
