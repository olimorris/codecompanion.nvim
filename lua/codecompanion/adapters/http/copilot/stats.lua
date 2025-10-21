local Curl = require("plenary.curl")

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local token = require("codecompanion.adapters.http.copilot.token")

local M = {}

local fmt = string.format

local PROGRESS_BAR_WIDTH = 20

---Calculate usage statistics
---@param entitlement number Total quota
---@param remaining number Remaining quota
---@return number used, number usage_percent
local function calculate_usage(entitlement, remaining)
  local used = entitlement - remaining
  local usage_percent = entitlement > 0 and (used / entitlement * 100) or 0
  return used, usage_percent
end

---Get Copilot usage statistics
---@return table|nil
local function get_statistics()
  log:debug("Copilot Adapter: Fetching Copilot usage statistics")

  local oauth_token = token.fetch().oauth_token

  local ok, response = pcall(function()
    return Curl.get("https://api.github.com/copilot_internal/user", {
      sync = true,
      headers = {
        Authorization = "Bearer " .. oauth_token,
        Accept = "*/*",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
    })
  end)

  if not ok then
    log:error("Copilot Adapter: Could not get stats: %s", response)
    return nil
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Copilot Adapter: Error parsing stats response: %s", response.body)
    return nil
  end

  return json
end

---Show Copilot usage statistics in a floating window
---@return nil
function M.show()
  local stats = get_statistics()
  if not stats then
    return vim.notify("Could not retrieve Copilot stats", vim.log.levels.ERROR)
  end

  local lines = {}
  local ui_utils = require("codecompanion.utils.ui")

  -- Progress bar for premium interactions
  -- @param percent number
  -- @param width number
  -- @return string
  local function make_progress_bar(percent, width)
    local filled = math.floor(width * percent / 100)
    return string.rep("█", filled) .. string.rep("░", width - filled)
  end

  local premium

  if stats.quota_snapshots.premium_interactions then
    premium = stats.quota_snapshots.premium_interactions
    table.insert(lines, "## Premium Interactions ")
    local used, usage_percent = calculate_usage(premium.entitlement, premium.remaining)
    table.insert(lines, fmt("- Used: %d / %d ", used, premium.entitlement))
    local bar = make_progress_bar(usage_percent, PROGRESS_BAR_WIDTH)
    table.insert(lines, fmt(" %s (%.1f%%)", bar, usage_percent))
    table.insert(lines, fmt("- Remaining: %d", premium.remaining))
    table.insert(lines, fmt("- Percentage: %.1f%%", premium.percent_remaining))
    if premium.unlimited then
      table.insert(lines, "- Status: Unlimited ")
    else
      table.insert(lines, "- Status: Limited")
    end
    if premium.overage_permitted then
      table.insert(lines, "- Overage: Permitted ")
    else
      table.insert(lines, "- Overage: Not Permitted ")
    end
    table.insert(lines, "")
  end

  if stats.quota_snapshots.chat then
    local chat = stats.quota_snapshots.chat
    table.insert(lines, "## Chat 󰭹 ")
    if chat.unlimited then
      table.insert(lines, "- Status: Unlimited ")
    else
      local used, usage_percent = calculate_usage(chat.entitlement, chat.remaining)
      table.insert(lines, fmt("- Used: %d / %d (%.1f%%)", used, chat.entitlement, usage_percent))
    end
    table.insert(lines, "")
  end

  if stats.quota_snapshots.completions then
    local completions = stats.quota_snapshots.completions
    table.insert(lines, "## Completions ")
    if completions.unlimited then
      table.insert(lines, "- Status: Unlimited ")
    else
      local used, usage_percent = calculate_usage(completions.entitlement, completions.remaining)
      table.insert(lines, fmt("- Used: %d / %d (%.1f%%)", used, completions.entitlement, usage_percent))
    end
  end

  if stats.quota_reset_date then
    table.insert(lines, "")
    table.insert(lines, fmt("> Quota resets on: %s", stats.quota_reset_date))
    local y, m, d = stats.quota_reset_date:match("^(%d+)%-(%d+)%-(%d+)$")
    if y and m and d then
      local days_left = (os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) }) - os.time()) / 86400
      local percent = math.max(0, math.min(((30 - days_left) / 30) * 100, 100))
      table.insert(lines, fmt("> %s (%d days left)", make_progress_bar(percent, 20), days_left))
    end
    table.insert(lines, "")
  end

  -- Create floating window
  local float_opts = {
    title = "   Copilot Stats ",
    lock = true,
    relative = "editor",
    row = "center",
    col = "center",
    window = {
      width = 43,
      height = math.min(#lines + 2, 20),
    },
    ignore_keymaps = false,
    style = "minimal",
  }
  local _, winnr = ui_utils.create_float(lines, float_opts)

  ---@param usage_percent number
  ---@return string
  local function get_usage_highlight(usage_percent)
    if usage_percent >= 80 then
      return "Error"
    else
      return "MoreMsg"
    end
  end

  -- Apply the highlights to the window
  vim.api.nvim_win_call(winnr, function()
    premium = stats.quota_snapshots.premium_interactions
    if premium and not premium.unlimited then
      local used, usage_percent = calculate_usage(premium.entitlement, premium.remaining)
      local highlight = get_usage_highlight(usage_percent)
      vim.fn.matchadd(highlight, fmt("- Used: %d / %d", used, premium.entitlement))
      local bar = make_progress_bar(usage_percent, PROGRESS_BAR_WIDTH)
      vim.fn.matchadd(highlight, fmt(" %s (%.1f%%)", bar, usage_percent))
    end
  end)
end

return M
