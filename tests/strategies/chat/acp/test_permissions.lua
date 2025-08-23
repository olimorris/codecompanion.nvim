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
    post_case = function()
      child.lua([[
	package.loaded["codecompanion.strategies.chat.acp.permissions"] = nil
	package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.diff"] = nil
	package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.wait"] = nil
]])
    end,
    post_once = child.stop,
  },
})

-- Utility to reset and mock modules inside child
local function with_mocks(lua_body)
  return child.lua(([[
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

    local interactions = require("codecompanion.strategies.chat.acp.permissions")
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
      local interactions = require("codecompanion.strategies.chat.acp.permissions")
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
      local interactions = require("codecompanion.strategies.chat.acp.permissions")
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

      local interactions = require("codecompanion.strategies.chat.acp.permissions")
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

    local interactions = require("codecompanion.strategies.chat.acp.permissions")
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

T["show_diff installs keymaps only for present kinds and triggers respond via mapping"] = function()
  local result = child.lua([[
    -- Minimal diff.create mock that returns accept/reject methods
    package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.diff"] = {
      create = function(bufnr, diff_id, opts)
        -- Ensure mappings will be set on the right buffer (current)
        return {
          accept = function() _G.__acp_accept_called = true end,
          reject = function() _G.__acp_reject_called = true end,
        }
      end
    }

    -- Don't auto-resolve; allow keymaps to drive decision
    package.loaded["codecompanion.strategies.chat.tools.catalog.helpers.wait"] = {
      for_decision = function(diff_id, events, cb, opts)
        _G.__acp_wait = { diff_id = diff_id, cb = cb, opts = opts }
      end
    }

    -- Configure ACP keymaps explicitly
    local cfg = require("codecompanion.config")
    cfg.strategies = cfg.strategies or {}
    cfg.strategies.chat = cfg.strategies.chat or {}
    cfg.strategies.chat.keymaps = {
      _acp_allow_always = { modes = { n = "ga" } },
      _acp_allow_once   = { modes = { n = "g2" } },
      _acp_reject_once  = { modes = { n = "g3" } },
      _acp_reject_always= { modes = { n = "g4" } },
    }

    -- Open the target file to ensure buffer/window focus exists
    vim.cmd.edit(_G.TEST_FILE)
    local bufnr = vim.api.nvim_get_current_buf()

    local interactions = require("codecompanion.strategies.chat.acp.permissions")

    local responded = {}
    local chat = { bufnr = 0 }
    -- Provide options missing 'reject_always' to validate dynamic mapping
    local request = {
      tool_call = {
        toolCallId = "tc-keys",
        kind = "edit",
        title = "Apply changes",
        status = "pending",
        content = { { type = "diff", path = _G.TEST_FILE, oldText = "old", newText = "new" } },
      },
      options = {
        { optionId = "allow_always_id", name = "Always", kind = "allow_always" },
        { optionId = "allow_once_id",   name = "Allow",  kind = "allow_once" },
        { optionId = "reject_once_id",  name = "Reject", kind = "reject_once" },
        -- Intentionally omit 'reject_always'
      },
      respond = function(option_id, canceled) responded = { option_id = option_id, canceled = canceled } end,
    }

    interactions.show_diff(chat, request)

    -- Check buffer-local mappings
    local function map_exists(lhs)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if m.lhs == lhs then return true end
      end
      return false
    end

    local has_g2 = map_exists("g2")     -- allow_once present -> should exist
    local has_g3 = map_exists("g3")     -- reject_once present -> should exist
    local has_g4 = map_exists("g4")     -- reject_always absent -> should NOT exist

    -- Trigger allow_once via 'g2'
    vim.api.nvim_feedkeys("g2", "n", false)
    vim.cmd("redraw") -- process feedkeys

    return {
      has_g2 = has_g2,
      has_g3 = has_g3,
      has_g4 = has_g4,
      responded = responded,
      accept_called = _G.__acp_accept_called == true,
    }
  ]])

  -- Mappings should exist only for present kinds
  h.eq(true, result.has_g2)
  h.eq(true, result.has_g3)
  h.eq(false, result.has_g4)

  -- Pressing g2 should accept with allow_once_id
  h.eq("allow_once_id", result.responded.option_id)
  h.eq(false, result.responded.canceled)
  h.eq(true, result.accept_called)
end

return T
