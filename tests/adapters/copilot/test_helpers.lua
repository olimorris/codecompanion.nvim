local copilot_helper = require("codecompanion.adapters.copilot.helpers")
local h = require("tests.helpers")

local new_set = MiniTest.new_set
T = new_set()

T["Copilot Helper Stats"] = new_set()

T["Copilot Helper Stats"]["can calculate usage percentages correctly"] = function()
  local entitlement, remaining = 300, 250
  local used = entitlement - remaining
  local usage_percent = entitlement > 0 and (used / entitlement * 100) or 0
  h.eq(50, used)
  -- 50/300 * 100 = 16.666... so we need to check the rounded value
  h.eq(16.7, math.floor(usage_percent * 10 + 0.5) / 10)

  local zero_entitlement = 0
  local zero_percent = zero_entitlement > 0 and (0 / zero_entitlement * 100) or 0
  h.eq(0, zero_percent)

  -- Test full usage
  local full_entitlement, no_remaining = 100, 0
  local full_used = full_entitlement - no_remaining
  local full_percent = full_entitlement > 0 and (full_used / full_entitlement * 100) or 0
  h.eq(100, full_used)
  h.eq(100.0, full_percent)
end

T["Copilot Helper Stats"]["can determine correct highlight colors based on usage"] = function()
  local function get_usage_highlight(usage_percent)
    if usage_percent >= 80 then
      return "Error"
    else
      return "MoreMsg"
    end
  end

  -- Test low usage (green)
  h.eq("MoreMsg", get_usage_highlight(16.7))
  h.eq("MoreMsg", get_usage_highlight(50))
  h.eq("MoreMsg", get_usage_highlight(79.9))
  -- Test high usage (red)
  h.eq("Error", get_usage_highlight(80))
  h.eq("Error", get_usage_highlight(85))
  h.eq("Error", get_usage_highlight(100))

  h.eq("MoreMsg", get_usage_highlight(0))
end

T["Copilot Helper Stats"]["show_copilot_stats handles overage_permitted for premium"] = function()
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

  -- Mock the get_copilot_stats function to return our test data
  local original_get_stats = copilot_helper.get_copilot_stats
  copilot_helper.get_copilot_stats = function()
    return mock_stats
  end

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

  -- Test the function
  copilot_helper.show_copilot_stats(function()
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

  -- Restore original functions
  vim.notify = original_notify
  copilot_helper.get_copilot_stats = original_get_stats
  ui.create_float = original_create_float
  vim.api.nvim_win_call = original_win_call
  vim.fn.matchadd = original_matchadd

  h.eq(true, found_overage, "Expected overage_permitted to be displayed in stats")
end

T["Copilot Helper Get Models"] = new_set()

T["Copilot Helper Get Models"]["retrieves models with correct structure"] = function()
  local mock_models = {
    {
      id = "model1",
      capabilities = { type = "chat", supports = { streaming = true, tool_calls = true, vision = true } },
      model_picker_enabled = true,
    },
    {
      id = "model2",
      capabilities = { type = "chat", supports = {} },
      model_picker_enabled = true,
    },
    {
      id = "model3",
      capabilities = { type = "completion" },
      model_picker_enabled = false,
    },
  }
  local curl = require("plenary.curl")
  local original_curl_get = curl.get
  curl.get = function(url, _)
    if url == "https://api.githubcopilot.com/models" then
      return {
        body = vim.json.encode({ data = mock_models }),
        status = 200,
      }
    else
      return { status = 404, body = "Not Found" }
    end
  end
  local utils = require("codecompanion.utils.adapters")
  local original_refresh_cache = utils.refresh_cache
  local refresh_cache_mock = function()
    return 0
  end
  utils.refresh_cache = refresh_cache_mock
  local mock_adapter = { url = "https://api.githubcopilot.com", headers = {} }
  local mock_get_and_authorize_token = function()
    return true -- Simulate successful token retrieval
  end
  local mock_oauth_token = "mock_oauth_token"

  local models = copilot_helper.get_models(mock_adapter, mock_get_and_authorize_token, mock_oauth_token)

  h.eq(2, vim.tbl_count(models), "Expected two models to be returned")
  h.eq({
    opts = {
      can_stream = true,
      can_use_tools = true,
      has_vision = true,
    },
  }, models.model1, "First model should match")
  h.eq({ opts = {} }, models.model2, "Second model should match")

  -- Restore original function
  utils.refresh_cache = original_refresh_cache
  curl.get = original_curl_get
end

T["Copilot Helper Get Models"]["returns empty table when Copilot token refresh is not OK"] = function()
  local mock_adapter = { url = "https://api.githubcopilot.com", headers = {} }
  local mock_get_and_authorize_token = function()
    return false -- Simulate unsuccessful token retrieval
  end
  local mock_oauth_token = "mock_oauth_token"

  local models = copilot_helper.get_models(mock_adapter, mock_get_and_authorize_token, mock_oauth_token)

  h.eq(0, vim.tbl_count(models), "Expected no models to be returned")
end

return T
