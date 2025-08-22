-- tests/strategies/chat/helpers/test_acp_interactions.lua
local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.TEST_FILE = vim.fs.joinpath('tests/stubs/test_acp_interactions', 'file.txt')
      ]])
    end,
    post_once = child.stop,
  },
})

-- Utility to reset and mock modules inside child
local function with_mocks(lua_body)
  return child.lua(([[
    -- Reset modules
    package.loaded["codecompanion.strategies.chat.helpers.acp_interactions"] = nil
    package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.diff"] = nil
    package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.wait"] = nil

    -- Capture table
    _G.__capt = {}

    -- Mock diff helper: capture bufnr and return a simple diff object
    package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.diff"] = {
      create = function(bufnr, diff_id, opts)
        _G.__capt.diff_create = { bufnr = bufnr, diff_id = diff_id, old = opts and opts.original_content or nil }
        return {
          accept = function() _G.__capt.accept_called = true end,
          reject = function() _G.__capt.reject_called = true end,
        }
      end
    }

    %s

    local interactions = require("codecompanion.strategies.chat.helpers.acp_interactions")
    return (function()
      %s
    end)()
  ]]):format(lua_body.wait_mock, lua_body.body))
end

T["show_diff maps accept to allow_* optionId"] = function()
  local result = with_mocks({
    wait_mock = [[
      -- Immediately signal accepted
      package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.wait"] = {
        for_decision = function(diff_id, events, cb, opts) cb({ accepted = true }) end
      }
    ]],
    body = [[
      local interactions = require("codecompanion.strategies.chat.helpers.acp_interactions")
      local responded = {}
      local chat = { bufnr = 0 }
      local request = {
        tool_call = {
          toolCallId = "tc-1",
          kind = "edit",
          title = "Apply changes",
          status = "pending",
          content = { { type = "diff", path = _G.TEST_FILE, oldText = "old", newText = "new" } },
        },
        options = {
          { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
          { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
        },
        respond = function(option_id, canceled) responded = { option_id = option_id, canceled = canceled } end,
      }

      interactions.show_diff(chat, request)
      return { option_id = responded.option_id, canceled = responded.canceled, accept_called = _G.__capt.accept_called == true }
    ]],
  })

  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
  h.eq(true, result.accept_called)
end

T["show_diff maps reject to reject_* optionId"] = function()
  local result = with_mocks({
    wait_mock = [[
      -- Immediately signal rejected
      package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.wait"] = {
        for_decision = function(diff_id, events, cb, opts) cb({ accepted = false, timeout = false }) end
      }
    ]],
    body = [[
      local interactions = require("codecompanion.strategies.chat.helpers.acp_interactions")
      local responded = {}
      local chat = { bufnr = 0 }
      local request = {
        tool_call = {
          toolCallId = "tc-2",
          kind = "edit",
          title = "Apply changes",
          status = "pending",
          content = { { type = "diff", path = _G.TEST_FILE, oldText = "old", newText = "new" } },
        },
        options = {
          { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
          { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
        },
        respond = function(option_id, canceled) responded = { option_id = option_id, canceled = canceled } end,
      }

      interactions.show_diff(chat, request)
      return { option_id = responded.option_id, canceled = responded.canceled, reject_called = _G.__capt.reject_called == true }
    ]],
  })

  h.eq("reject_once_id", result.option_id)
  h.eq(false, result.canceled)
  h.eq(true, result.reject_called)
end

T["show_diff reuses existing buffer for file path"] = function()
  local result = with_mocks({
    wait_mock = [[
      package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.wait"] = {
        for_decision = function(diff_id, events, cb, opts) cb({ accepted = true }) end
      }
    ]],
    body = [[
      -- Open the file to create an existing buffer and window
      vim.cmd.edit(_G.TEST_FILE)
      local existing_buf = vim.api.nvim_get_current_buf()

      local interactions = require("codecompanion.strategies.chat.helpers.acp_interactions")
      local responded = {}
      local chat = { bufnr = 0 }
      local request = {
        tool_call = {
          toolCallId = "tc-3",
          kind = "edit",
          title = "Apply changes",
          status = "pending",
          content = { { type = "diff", path = _G.TEST_FILE, oldText = "old", newText = "new" } },
        },
        options = {
          { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
          { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
        },
        respond = function(option_id, canceled) responded = { option_id = option_id, canceled = canceled } end,
      }

      interactions.show_diff(chat, request)

      local captured = _G.__capt.diff_create or {}
      return { used_bufnr = captured.bufnr, existing_buf = existing_buf, option_id = responded.option_id }
    ]],
  })

  h.eq(result.existing_buf, result.used_bufnr)
  h.eq("allow_once_id", result.option_id)
end

T["show_diff cancels when no diff content"] = function()
  local result = child.lua([[
    package.loaded["codecompanion.strategies.chat.helpers.acp_interactions"] = nil

    local interactions = require("codecompanion.strategies.chat.helpers.acp_interactions")
    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-4",
        kind = "execute",
        title = "Run command",
        status = "pending",
        content = {}, -- no diff entries
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled) responded = { option_id = option_id, canceled = canceled } end,
    }

    interactions.show_diff(chat, request)
    return responded
  ]])

  h.eq(nil, result.option_id)
  h.eq(true, result.canceled)
end

return T
