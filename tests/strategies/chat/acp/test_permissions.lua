local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Minimal config surface used by permissions.lua
        local cfg = require("codecompanion.config")
        cfg.display = cfg.display or {}
        cfg.display.icons = cfg.display.icons or { warning = "!" }
        cfg.display.chat = cfg.display.chat or {}
        cfg.display.chat.child_window = cfg.display.chat.child_window or {
          width = 60, height = 12, row = "center", col = "center", relative = "editor", opts = {},
        }
        -- Sensible default to avoid timeouts during tests
        cfg.strategies = cfg.strategies or {}
        cfg.strategies.chat = cfg.strategies.chat or {}
        cfg.strategies.chat.opts = cfg.strategies.chat.opts or {}
        cfg.strategies.chat.opts.acp_timeout_response = "reject_once"
      ]])
    end,
    post_case = function()
      child.lua([[
        package.loaded["codecompanion.strategies.chat.acp.permissions"] = nil
        package.loaded["codecompanion.providers.diff.inline"] = nil
        package.loaded["codecompanion.strategies.chat.helpers.wait"] = nil
        package.loaded["codecompanion.utils.ui"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

-- Small helper to set up mocks per-case and run body inside child
local function with_mocks(opts)
  opts = opts or {}
  return child.lua(([[
    _G.__CAPT = {}

    -- Mock Inline diff provider
    package.loaded["codecompanion.providers.diff.inline"] = {
      new = function(args)
        _G.__CAPT.inline_new = {
          bufnr = args.bufnr,
          id = args.id,
          contents = args.contents,
        }
        return {
          accept = function(_) _G.__CAPT.accept_called = true end,
          reject = function(_) _G.__CAPT.reject_called = true end,
        }
      end
    }

    -- Mock UI float creator: create real scratch buffer + floating window
    package.loaded["codecompanion.utils.ui"] = {
      create_float = function(lines, _opts)
        local bufnr = vim.api.nvim_create_buf(false, true)
        if lines then
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
        end
        local w = vim.api.nvim_open_win(bufnr, true, {
          relative = "editor",
          width = 60, height = 12,
          row = 1, col = 1,
          style = "minimal", border = "single",
        })
        return bufnr, w
      end
    }

    -- Mock wait helper
    package.loaded["codecompanion.strategies.chat.helpers.wait"] = {
      for_decision = function(diff_id, _events, cb, _opts)
        _G.__CAPT.wait = { id = diff_id, cb = cb }
        %s
      end
    }

    local permissions = require("codecompanion.strategies.chat.acp.permissions")

    return (function()
      %s
    end)()
  ]]):format(opts.wait_behavior or "", opts.body))
end

T["accept path selects allow_* and calls diff.accept"] = function()
  local result = with_mocks({
    wait_behavior = [[
      -- Resolve immediately as accepted
      cb({ accepted = true })
    ]],
    body = [[
      local responded = {}
      local chat = { bufnr = 0 }
      local request = {
        tool_call = {
          toolCallId = "tc-accept",
          kind = "edit",
          title = "Apply changes",
          status = "pending",
          content = { { type = "diff", path = "file.txt", oldText = "old", newText = "new" } },
        },
        options = {
          { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
          { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
        },
        respond = function(option_id, canceled)
          responded = { option_id = option_id, canceled = canceled }
        end,
      }

      permissions.show_diff(chat, request)

      return {
        option_id = responded.option_id,
        canceled = responded.canceled,
        accept_called = _G.__CAPT.accept_called == true,
        inline_bufnr = _G.__CAPT.inline_new and _G.__CAPT.inline_new.bufnr or nil,
        original_had_old = _G.__CAPT.inline_new and _G.__CAPT.inline_new.contents and _G.__CAPT.inline_new.contents[1] == "old",
      }
    ]],
  })

  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
  h.eq(true, result.accept_called)
  h.is_true(type(result.inline_bufnr) == "number")
  h.eq(true, result.original_had_old)
end

T["reject path selects reject_* and calls diff.reject"] = function()
  local result = with_mocks({
    wait_behavior = [[
      -- Resolve immediately as rejected (no timeout)
      cb({ accepted = false, timeout = false })
    ]],
    body = [[
      local responded = {}
      local chat = { bufnr = 0 }
      local request = {
        tool_call = {
          toolCallId = "tc-reject",
          kind = "edit",
          title = "Apply changes",
          status = "pending",
          content = { { type = "diff", path = "file.txt", oldText = "old", newText = "new" } },
        },
        options = {
          { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
          { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
        },
        respond = function(option_id, canceled)
          responded = { option_id = option_id, canceled = canceled }
        end,
      }

      permissions.show_diff(chat, request)

      return {
        option_id = responded.option_id,
        canceled = responded.canceled,
        reject_called = _G.__CAPT.reject_called == true,
      }
    ]],
  })

  h.eq("reject_once_id", result.option_id)
  h.eq(false, result.canceled)
  h.eq(true, result.reject_called)
end

T["cancels when no diff content"] = function()
  local result = with_mocks({
    wait_behavior = [[
      -- Shouldn't be called; no diff -> immediate cancel
    ]],
    body = [[
      local responded = {}
      local chat = { bufnr = 0 }
      local request = {
        tool_call = {
          toolCallId = "tc-nodiff",
          kind = "execute",
          title = "Run command",
          status = "pending",
          content = {}, -- no diff entries
        },
        options = {
          { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
          { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
        },
        respond = function(option_id, canceled)
          responded = { option_id = option_id, canceled = canceled }
        end,
      }

      permissions.show_diff(chat, request)
      return responded
    ]],
  })

  h.eq(nil, result.option_id)
  h.eq(true, result.canceled)
end

T["installs keymaps only for present kinds and mapping triggers respond"] = function()
  local result = with_mocks({
    wait_behavior = [[
      -- Don't resolve automatically; let keymaps drive the decision
      -- We keep the callback stored in _G.__CAPT.wait
    ]],
    body = [[
      -- Configure ACP mappings
      local cfg = require("codecompanion.config")
      cfg.strategies.chat.keymaps = {
        _acp_allow_always = { modes = { n = "g1" } },
        _acp_allow_once   = { modes = { n = "g2" } },
        _acp_reject_once  = { modes = { n = "g3" } },
        -- Intentionally omit 'reject_always'
      }

      local responded = {}
      local chat = { bufnr = 0 }
      local request = {
        tool_call = {
          toolCallId = "tc-keys",
          kind = "edit",
          title = "Apply changes",
          status = "pending",
          content = { { type = "diff", path = "file.txt", oldText = "old", newText = "new" } },
        },
        options = {
          { optionId = "allow_always_id", name = "Always", kind = "allow_always" },
          { optionId = "allow_once_id",   name = "Allow",  kind = "allow_once" },
          { optionId = "reject_once_id",  name = "Reject", kind = "reject_once" },
        },
        respond = function(option_id, canceled)
          _G.__CAPT.responded = { option_id = option_id, canceled = canceled }
        end,
      }

      local permissions = require("codecompanion.strategies.chat.acp.permissions")
      permissions.show_diff(chat, request)

      -- The float and buffer were created in ui.create_float; switch to it to use buffer-local mappings
      local bufnr = _G.__CAPT.inline_new.bufnr
      local winnr
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
          winnr = win
          break
        end
      end
      _G.__CAPT.win = winnr  -- store for later keypress

      -- Verify mappings exist as expected
      local function map_exists(lhs)
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
          if m.lhs == lhs then return true end
        end
        return false
      end
      local has_g1 = map_exists("g1") -- allow_always present
      local has_g2 = map_exists("g2") -- allow_once present
      local has_g3 = map_exists("g3") -- reject_once present
      local has_g4 = map_exists("g4") -- reject_always absent

      return {
        has_g1 = has_g1,
        has_g2 = has_g2,
        has_g3 = has_g3,
        has_g4 = has_g4,
      }
    ]],
  })

  h.eq(true, result.has_g1)
  h.eq(true, result.has_g2)
  h.eq(true, result.has_g3)
  h.eq(false, result.has_g4)

  child.lua([[ if _G.__CAPT.win then vim.api.nvim_set_current_win(_G.__CAPT.win) end ]])
  child.type_keys("g2")
  child.lua([[ vim.cmd("redraw") ]])

  -- Read back what respond() captured and whether accept() was called
  local responded = child.lua_get([[_G.__CAPT.responded]])
  local accept_called = child.lua_get([[ _G.__CAPT.accept_called == true ]])

  -- Pressing g2 should accept with allow_once_id
  h.eq("allow_once_id", responded.option_id)
  h.eq(false, responded.canceled)
  h.is_true(accept_called)
end

return T
