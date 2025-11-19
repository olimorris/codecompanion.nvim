local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local new_set = MiniTest.new_set
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Global, mutable test fixtures
        _G.mock_stats = {
          quota_snapshots = {
            premium_interactions = {
              entitlement = 500,
              remaining = 100,
              percent_remaining = 20,
              unlimited = false,
              overage_permitted = true,
            },
            chat = {
              entitlement = 100,
              remaining = 50,
              unlimited = false,
            },
            completions = {
              entitlement = 100,
              remaining = 80,
              unlimited = false,
            },
          },
          quota_reset_date = "2099-12-31",
        }
        _G.fail_request = false

        -- Capture points
        _G.captured_lines = {}
        _G.captured_matchadds = {}
        _G.notify_args = {}

        -- Stub dependencies before requiring subject module
        package.loaded["plenary.curl"] = {
          get = function(_, _)
            if _G.fail_request then
              error("network error")
            end
            return { status = 200, body = vim.json.encode(_G.mock_stats) }
          end,
        }

        package.loaded["codecompanion.adapters.http.copilot.token"] = {
          fetch = function() return { oauth_token = "dummy" } end,
        }

        package.loaded["codecompanion.config"] = {
          adapters = { http = { opts = { allow_insecure = false, proxy = nil } } },
        }

        local ui = {}
        ui.create_float = function(lines, _)
          _G.captured_lines = vim.deepcopy(lines)
          return 1, 1
        end
        package.loaded["codecompanion.utils.ui"] = ui

        -- Nvim API stubs
        _G._orig_win_call = vim.api.nvim_win_call
        vim.api.nvim_win_call = function(_, fn) return fn() end

        _G._orig_matchadd = vim.fn.matchadd
        vim.fn.matchadd = function(hl, pat)
          table.insert(_G.captured_matchadds, { hl = hl, pat = pat })
        end

        _G._orig_notify = vim.notify
        vim.notify = function(msg, level) _G.notify_args = { msg = msg, level = level } end

        -- Subject under test
        stats = require("codecompanion.adapters.http.copilot.stats")
      ]])
    end,
    post_once = child.stop,
  },
})

T["show: displays premium overage permitted"] = function()
  local ok = child.lua([[
    -- Ensure overage permitted
    _G.mock_stats.quota_snapshots.premium_interactions.overage_permitted = true
    stats.show()
    for _, line in ipairs(_G.captured_lines or {}) do
      if line:match("Overage:%s*Permitted") then
        return true
      end
    end
    return false
  ]])

  h.eq(true, ok, "Expected 'Overage: Permitted' to be displayed")
end

T["show: highlights when usage >= 80%"] = function()
  local result = child.lua([[
    -- 90% usage -> should use 'Error' highlight
    _G.mock_stats.quota_snapshots.premium_interactions.entitlement = 100
    _G.mock_stats.quota_snapshots.premium_interactions.remaining = 10
    _G.mock_stats.quota_snapshots.premium_interactions.unlimited = false

    -- Reset captures
    _G.captured_matchadds = {}
    stats.show()

    local has_bar = false
    for _, call in ipairs(_G.captured_matchadds or {}) do
      -- Match "(90.0%)" — '(' and ')' are magic in Lua patterns, and '%' is escaped as '%%'
      if call.hl == "Error" and call.pat:match("%(90%.0%%%)") then
        has_bar = true
      end
    end
    return has_bar
  ]])

  h.eq(true, result, "Expected 'Error' highlight for 90% usage")
end

T["show: computes chat and completions usage correctly"] = function()
  local res = child.lua([[
    -- Premium irrelevant; ensure not unlimited to allow highlights but we only assert lines
    _G.mock_stats.quota_snapshots.premium_interactions.entitlement = 500
    _G.mock_stats.quota_snapshots.premium_interactions.remaining = 100
    _G.mock_stats.quota_snapshots.premium_interactions.unlimited = false

    -- Chat: 50 entitlement, 20 remaining => used 30 (60.0%)
    _G.mock_stats.quota_snapshots.chat = {
      entitlement = 50,
      remaining = 20,
      unlimited = false,
    }
    -- Completions: 100 entitlement, 75 remaining => used 25 (25.0%)
    _G.mock_stats.quota_snapshots.completions = {
      entitlement = 100,
      remaining = 75,
      unlimited = false,
    }

    stats.show()

    local found_chat = false
    local found_comp = false
    for _, line in ipairs(_G.captured_lines or {}) do
      -- Match "- Used: 30 / 50 (60.0%)"
      if line:match("^%- Used:%s*30%s*/%s*50%s*%(60%.0%%%)$") then
        found_chat = true
      end
      -- Match "- Used: 25 / 100 (25.0%)"
      if line:match("^%- Used:%s*25%s*/%s*100%s*%(25%.0%%%)$") then
        found_comp = true
      end
    end
    return found_chat and found_comp
  ]])

  h.eq(true, res, "Expected chat/completions usage to be computed from their own quotas")
end

T["show: notifies on retrieval failure"] = function()
  local msg = child.lua([[
    _G.fail_request = true
    _G.notify_args = {}
    stats.show()
    _G.fail_request = false
    return _G.notify_args.msg or ""
  ]])

  h.eq("Could not retrieve Copilot stats", msg, "Expected error notification when retrieval fails")
end

T["show: works without premium_interactions"] = function()
  local res = child.lua([[
    _G.mock_stats.quota_snapshots.premium_interactions = nil
    _G.captured_matchadds = {}
    stats.show()

    -- No highlights should be applied when premium is missing
    local no_highlights = (#_G.captured_matchadds == 0)
    local has_chat_header = false
    for _, line in ipairs(_G.captured_lines or {}) do
      if line:match("^##%s*Chat") then has_chat_header = true end
    end
    return no_highlights and has_chat_header
  ]])

  h.eq(true, res, "Expected no highlights and Chat section present without premium stats")
end

T["show: displays limited account stats"] = function()
  local res = child.lua([[
    -- Simulate limited account
    _G.mock_stats.access_type_sku = "free_limited_copilot"
    _G.mock_stats.monthly_quotas = { chat = 10, completions = 20 }
    _G.mock_stats.limited_user_quotas = { chat = 3, completions = 5 }
    _G.mock_stats.limited_user_reset_date = "2099-11-30"
    _G.captured_lines = {}
    _G.captured_matchadds = {}

    stats.show()

    local found_header = false
    local found_chat = false
    local found_completions = false
    local found_reset = false
    for _, line in ipairs(_G.captured_lines or {}) do
      if line:match("Limited Copilot") then found_header = true end
      if line:match("Chat") then found_chat = true end
      if line:match("Completions") then found_completions = true end
      if line:match("2099%-11%-30") then found_reset = true end
    end
    -- Should not highlight anything for limited
    local no_highlights = (#_G.captured_matchadds == 0)
    return found_header and found_chat and found_completions and found_reset and no_highlights
  ]])

  h.eq(true, res, "Expected limited account stats to be displayed with no highlights")
end

return T
