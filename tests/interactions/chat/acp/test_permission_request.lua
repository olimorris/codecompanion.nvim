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
        cfg.display.chat.floating_window = cfg.display.chat.floating_window or {
          width = 60, height = 12, row = "center", col = "center", relative = "editor", opts = {},
        }
        cfg.display.chat.tool_approval_window = cfg.display.chat.tool_approval_window or {
          border = "rounded", style = "minimal", relative = "editor",
          opts = { wrap = true, cursorline = false },
        }
        cfg.display.diff.window = cfg.display.diff.window or {}
        cfg.interactions = cfg.interactions or {}
        cfg.interactions.chat = cfg.interactions.chat or {}
        cfg.interactions.chat.opts = cfg.interactions.chat.opts or {}
        cfg.interactions.chat.keymaps = cfg.interactions.chat.keymaps or {}
        cfg.interactions.inline = cfg.interactions.inline or {}
        cfg.interactions.shared.keymaps = cfg.interactions.shared.keymaps or {
          next_hunk = { modes = { n = "}" } },
          previous_hunk = { modes = { n = "{" } },
          accept_change = { modes = { n = "ga" } },
          reject_change = { modes = { n = "gr" } },
          always_accept = { modes = { n = "gA" } },
        }

        -- Helper to focus the first floating window (confirm dialogs now open unfocused)
        _G.__focus_float = function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local c = vim.api.nvim_win_get_config(win)
            if c.relative and c.relative ~= "" then
              vim.api.nvim_set_current_win(win)
              return
            end
          end
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        -- Clean up any floating windows
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) then
            local cfg = vim.api.nvim_win_get_config(win)
            if cfg.relative and cfg.relative ~= "" then
              pcall(vim.api.nvim_win_close, win, true)
            end
          end
        end
        -- Unload modules
        package.loaded["codecompanion.interactions.chat.acp.request_permission"] = nil
        package.loaded["codecompanion.utils.ui"] = nil
        package.loaded["codecompanion.helpers"] = nil
        package.loaded["codecompanion.diff"] = nil
        package.loaded["codecompanion.diff.ui"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

-- ---------------------------------------------------------------------------
-- Confirm dialog (non-diff) tests
-- ---------------------------------------------------------------------------

T["no diff -> confirm dialog -> return selected option"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm = function(_, choices, callback)
      callback(choices[1].value)
    end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-nodiff",
        kind = "execute",
        title = "Run command",
        status = "pending",
        content = {},
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)
    return responded
  ]])

  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
end

T["no diff -> confirm dialog -> reject option"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm = function(_, choices, callback)
      callback(choices[2].value)
    end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-nodiff",
        kind = "execute",
        title = "Run command",
        status = "pending",
        content = {},
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)
    return responded
  ]])

  h.eq("reject_once_id", result.option_id)
  h.eq(false, result.canceled)
end

T["no diff -> confirm dialog -> cancel"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm = function(_, _, callback) callback(nil) end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-nodiff",
        kind = "execute",
        title = "Run command",
        status = "pending",
        content = {},
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)
    return responded
  ]])

  h.eq(nil, result.option_id)
  h.eq(true, result.canceled)
end

T["no diff -> choices have correct label, value and default"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")
    local captured = {}
    ui_utils.confirm = function(_, choices, callback)
      captured = choices
      callback(nil)
    end

    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-1",
        kind = "execute",
        title = "Run command",
        status = "pending",
        content = {},
      },
      options = {
        { optionId = "aa_id", name = "Always", kind = "allow_always" },
        { optionId = "ao_id", name = "Allow", kind = "allow_once" },
        { optionId = "ro_id", name = "Reject", kind = "reject_once" },
        { optionId = "ra_id", name = "Never", kind = "reject_always" },
      },
      respond = function() end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)
    return captured
  ]])

  h.eq("Allow always", result[1].label)
  h.eq("aa_id", result[1].value)

  h.eq("Allow", result[2].label)
  h.eq("ao_id", result[2].value)
  h.eq(true, result[2].default)

  h.eq("Reject", result[3].label)
  h.eq("ro_id", result[3].value)

  h.eq("Reject always", result[4].label)
  h.eq("ra_id", result[4].value)
end

-- ---------------------------------------------------------------------------
-- Cancel confirm tests
-- ---------------------------------------------------------------------------

T["cancel_confirm -> cancels open dialog without calling callback"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")

    local called = false
    ui_utils.confirm("Test", { { label = "OK", value = "ok" } }, function()
      called = true
    end, { key = "test_key" })

    ui_utils.cancel_confirm("test_key")

    -- Give vim.schedule a chance to fire
    vim.wait(50, function() return false end, 10)
    return called
  ]])

  h.eq(false, result)
end

T["cancel_confirm -> cancels multiple dialogs for same key"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")

    local call_count = 0
    for _ = 1, 3 do
      ui_utils.confirm("Test", { { label = "OK", value = "ok" } }, function()
        call_count = call_count + 1
      end, { key = "multi_key" })
    end

    -- Count floating windows before cancel
    local floats_before = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        floats_before = floats_before + 1
      end
    end

    ui_utils.cancel_confirm("multi_key")

    vim.wait(50, function() return false end, 10)

    -- Count floating windows after cancel
    local floats_after = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative and cfg.relative ~= "" then
          floats_after = floats_after + 1
        end
      end
    end

    return { call_count = call_count, floats_before = floats_before, floats_after = floats_after }
  ]])

  h.eq(0, result.call_count)
  h.eq(3, result.floats_before)
  h.eq(0, result.floats_after)
end

T["cancel_confirm -> no-op for unknown key"] = function()
  -- Should not error
  child.lua([[
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.cancel_confirm("nonexistent_key")
  ]])
end

-- ---------------------------------------------------------------------------
-- Real confirm dialog interaction tests
-- ---------------------------------------------------------------------------

T["confirm -> opens floating window with footer buttons"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")

    ui_utils.confirm("Test prompt", {
      { label = "Yes", value = "yes" },
      { label = "No", value = "no" },
    }, function() end)

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        return {
          has_float = true,
          has_footer = cfg.footer ~= nil,
          border = cfg.border,
        }
      end
    end
    return { has_float = false }
  ]])

  h.eq(true, result.has_float)
  h.eq(true, result.has_footer)
end

T["confirm -> Enter selects the default choice"] = function()
  child.lua([[
    _G.__selected = nil
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm("Pick one", {
      { label = "First", value = "first" },
      { label = "Second", value = "second", default = true },
      { label = "Third", value = "third" },
    }, function(value)
      _G.__selected = value
    end)
  ]])

  child.lua([[_G.__focus_float()]])
  child.type_keys("<CR>")
  child.lua([[vim.wait(100, function() return _G.__selected ~= nil end, 10)]])

  local selected = child.lua_get([[_G.__selected]])
  h.eq("second", selected)
end

T["confirm -> Tab cycles to next choice"] = function()
  child.lua([[
    _G.__selected = nil
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm("Pick one", {
      { label = "A", value = "a", default = true },
      { label = "B", value = "b" },
      { label = "C", value = "c" },
    }, function(value)
      _G.__selected = value
    end)
  ]])

  child.lua([[_G.__focus_float()]])
  child.type_keys("<Tab>")
  child.type_keys("<CR>")
  child.lua([[vim.wait(100, function() return _G.__selected ~= nil end, 10)]])

  local selected = child.lua_get([[_G.__selected]])
  h.eq("b", selected)
end

T["confirm -> S-Tab cycles to previous choice"] = function()
  child.lua([[
    _G.__selected = nil
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm("Pick one", {
      { label = "A", value = "a" },
      { label = "B", value = "b" },
      { label = "C", value = "c" },
    }, function(value)
      _G.__selected = value
    end)
  ]])

  -- Default is index 1 (A), S-Tab wraps to index 3 (C)
  child.lua([[_G.__focus_float()]])
  child.type_keys("<S-Tab>")
  child.type_keys("<CR>")
  child.lua([[vim.wait(100, function() return _G.__selected ~= nil end, 10)]])

  local selected = child.lua_get([[_G.__selected]])
  h.eq("c", selected)
end

T["confirm -> number key selects directly"] = function()
  child.lua([[
    _G.__selected = nil
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm("Pick one", {
      { label = "A", value = "a" },
      { label = "B", value = "b" },
      { label = "C", value = "c" },
    }, function(value)
      _G.__selected = value
    end)
  ]])

  child.lua([[_G.__focus_float()]])
  child.type_keys("3")
  child.lua([[vim.wait(100, function() return _G.__selected ~= nil end, 10)]])

  local selected = child.lua_get([[_G.__selected]])
  h.eq("c", selected)
end

T["confirm -> Esc cancels with nil"] = function()
  child.lua([[
    _G.__selected = "not_called"
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm("Pick one", {
      { label = "A", value = "a" },
    }, function(value)
      _G.__selected = value
    end)
  ]])

  child.lua([[_G.__focus_float()]])
  child.type_keys("<Esc>")
  child.lua([[vim.wait(100, function() return _G.__selected ~= "not_called" end, 10)]])

  local selected = child.lua_get([[_G.__selected]])
  h.eq(vim.NIL, selected)
end

T["confirm -> q cancels with nil"] = function()
  child.lua([[
    _G.__selected = "not_called"
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm("Pick one", {
      { label = "A", value = "a" },
    }, function(value)
      _G.__selected = value
    end)
  ]])

  child.lua([[_G.__focus_float()]])
  child.type_keys("q")
  child.lua([[vim.wait(100, function() return _G.__selected ~= "not_called" end, 10)]])

  local selected = child.lua_get([[_G.__selected]])
  h.eq(vim.NIL, selected)
end

T["confirm -> normalizes plain string choices"] = function()
  child.lua([[
    _G.__selected = nil
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm("Pick one", { "Yes", "No" }, function(value)
      _G.__selected = value
    end)
  ]])

  -- Default is index 1, Enter selects "Yes" (label == value for strings)
  child.lua([[_G.__focus_float()]])
  child.type_keys("<CR>")
  child.lua([[vim.wait(100, function() return _G.__selected ~= nil end, 10)]])

  local selected = child.lua_get([[_G.__selected]])
  h.eq("Yes", selected)
end

-- ---------------------------------------------------------------------------
-- Diff flow tests
-- ---------------------------------------------------------------------------

T["diff flow -> shows diff and installs keymaps"] = function()
  local result = child.lua([[
    -- Configure ACP mappings
    local cfg = require("codecompanion.config")
    cfg.interactions.chat.keymaps = {
      _acp_allow_always = { modes = { n = "g1" } },
      _acp_allow_once   = { modes = { n = "g2" } },
      _acp_reject_once  = { modes = { n = "g3" } },
    }

    _G.__responded = nil
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-diff",
        kind = "edit",
        title = "Apply changes",
        status = "pending",
        content = { { type = "diff", path = "file.txt", oldText = "old line", newText = "new line" } },
      },
      options = {
        { optionId = "allow_always_id", name = "Always", kind = "allow_always" },
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        _G.__responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)

    -- Find the diff floating window
    local diff_bufnr, diff_winnr
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        diff_winnr = win
        diff_bufnr = vim.api.nvim_win_get_buf(win)
        break
      end
    end

    -- Check keymaps exist on the buffer
    local function map_exists(bufnr, lhs)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if m.lhs == lhs then return true end
      end
      return false
    end

    return {
      has_diff_window = diff_winnr ~= nil,
      has_g1 = diff_bufnr and map_exists(diff_bufnr, "g1") or false,
      has_g2 = diff_bufnr and map_exists(diff_bufnr, "g2") or false,
      has_g3 = diff_bufnr and map_exists(diff_bufnr, "g3") or false,
      has_nav_next = diff_bufnr and map_exists(diff_bufnr, "}") or false,
      has_nav_prev = diff_bufnr and map_exists(diff_bufnr, "{") or false,
      has_close = diff_bufnr and map_exists(diff_bufnr, "q") or false,
      diff_bufnr = diff_bufnr,
      diff_winnr = diff_winnr,
    }
  ]])

  h.eq(true, result.has_diff_window)
  h.eq(true, result.has_g1)
  h.eq(true, result.has_g2)
  h.eq(true, result.has_g3)
  h.eq(true, result.has_nav_next)
  h.eq(true, result.has_nav_prev)
  h.eq(true, result.has_close)
end

T["diff flow -> keymap triggers respond with correct option"] = function()
  -- Set up the diff
  child.lua([[
    -- Configure ACP mappings
    local cfg = require("codecompanion.config")
    cfg.interactions.chat.keymaps = {
      _acp_allow_always = { modes = { n = "g1" } },
      _acp_allow_once   = { modes = { n = "g2" } },
      _acp_reject_once  = { modes = { n = "g3" } },
    }

    _G.__responded = nil
    _G.__diff_winnr = nil
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-diff",
        kind = "edit",
        title = "Apply changes",
        status = "pending",
        content = { { type = "diff", path = "file.txt", oldText = "old", newText = "new" } },
      },
      options = {
        { optionId = "allow_always_id", name = "Always", kind = "allow_always" },
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        _G.__responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)

    -- Find and focus the diff window
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        _G.__diff_winnr = win
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  ]])

  -- Press g2 to select "allow_once"
  child.type_keys("g2")

  local result = child.lua_get([[_G.__responded]])
  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
end

T["diff flow -> reject keymap triggers respond"] = function()
  child.lua([[
    -- Configure ACP mappings
    local cfg = require("codecompanion.config")
    cfg.interactions.chat.keymaps = {
      _acp_allow_once  = { modes = { n = "g2" } },
      _acp_reject_once = { modes = { n = "g3" } },
    }

    _G.__responded = nil
    _G.__diff_winnr = nil
    _G.__diff_bufnr = nil
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-diff",
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
        _G.__responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)

    -- Find the diff window
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local wincfg = vim.api.nvim_win_get_config(win)
      if wincfg.relative and wincfg.relative ~= "" then
        _G.__diff_winnr = win
        _G.__diff_bufnr = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  ]])

  -- Verify we found the window
  local winnr = child.lua_get([[_G.__diff_winnr]])
  h.is_true(type(winnr) == "number", "Should find diff window")

  -- Press g3 to reject (since we have that keymap)
  child.type_keys("g3")

  -- Wait for response
  child.lua([[vim.wait(100, function() return _G.__responded ~= nil end, 10)]])

  local result = child.lua_get([[_G.__responded]])
  h.eq("reject_once_id", result.option_id)
  h.eq(false, result.canceled)
end

T["diff flow -> empty oldText and newText does not show diff"] = function()
  local result = child.lua([[
    local ui_utils = require("codecompanion.utils.ui")
    ui_utils.confirm = function(_, choices, callback)
      callback(choices[1].value)
    end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-empty",
        kind = "edit",
        title = "Empty diff",
        status = "pending",
        content = { { type = "diff", path = "file.txt", oldText = "", newText = "" } },
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)

    -- Check no floating window was created
    local has_float = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        has_float = true
        break
      end
    end

    return {
      has_float = has_float,
      option_id = responded.option_id,
      canceled = responded.canceled,
    }
  ]])

  -- Empty diff should fall through to confirm dialog
  h.eq(false, result.has_float)
  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
end

return T
