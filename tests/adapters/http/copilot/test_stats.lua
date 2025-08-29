local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local new_set = MiniTest.new_set
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
      stats = require("codecompanion.adapters.http.copilot.stats")
    ]])
    end,
    post_once = child.stop,
  },
})

T["Copilot Stats"] = function()
  local result = child.lua([[
  -- Mock vim.notify to capture output
  local notify_called = false
  local notify_message = ""
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    notify_called = true
    notify_message = msg
  end

  -- Mock stats with overage_permitted
  local mock_stats = {
    quota_snapshots = {
      premium_interactions = {
        entitlement = 500,
        remaining = 100,
        percent_remaining = 20,
        unlimited = false,
        overage_permitted = true,
      },
    },
    quota_reset_date = "2024-02-15",
  }

  -- Mock UI creation to avoid actual window creation
  local ui = require("codecompanion.utils.ui")
  local original_create_float = ui.create_float
  local captured_lines = {}
  ui.create_float = function(lines, opts)
    captured_lines = lines
    return 1, 1 -- Return dummy buffer and window IDs
  end

  -- Mock vim.api.nvim_win_call to avoid window operations
  local original_win_call = vim.api.nvim_win_call
  vim.api.nvim_win_call = function(winnr, fn)
    return fn()
  end

  -- Mock vim.fn.matchadd to avoid highlighting operations
  local original_matchadd = vim.fn.matchadd
  vim.fn.matchadd = function() end

  -- Mock the stats output from the API
  stats.get = function()
    return mock_stats
  end

  -- Test the function
  stats.show(function()
    return true
  end, "test_token")

  -- Check that overage_permitted is displayed
  local found_overage = false
  for _, line in ipairs(captured_lines) do
    if line:match("overage.*permitted") or line:match("Overage.*Permitted") then
      found_overage = true
      break
    end
  end

  return found_overage
  ]])

  h.eq(true, result, "Expected overage_permitted to be displayed in stats")
end

return T
