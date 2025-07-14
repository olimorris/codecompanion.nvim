local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.adapters")
local M = {}

-- Cache variables
local _cached_models
local _cached_adapter
local _cache_expires
local _cache_file = vim.fn.tempname()
local PROGRESS_BAR_WIDTH = 20

---Function to reset the Copilot cache
---@return nil
function M.reset_cache()
  _cached_adapter = nil
end

---Calculate usage statistics
---@param entitlement number Total quota
---@param remaining number Remaining quota
---@return number used, number usage_percent
local function calculate_usage(entitlement, remaining)
  local used = entitlement - remaining
  local usage_percent = entitlement > 0 and (used / entitlement * 100) or 0
  return used, usage_percent
end

---Get a list of available Copilot models
---@param adapter CodeCompanion.Adapter
---@param get_and_authorize_token_fn function Function to get and authorize token
---@param oauth_token string The oauth token
---@return table
function M.get_models(adapter, get_and_authorize_token_fn, oauth_token)
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    return _cached_models
  end

  if not _cached_adapter then
    if not adapter then
      return {}
    end
    _cached_adapter = adapter
  end

  if not get_and_authorize_token_fn(adapter) then
    return {}
  end

  local url = "https://api.githubcopilot.com/models"
  local headers = vim.deepcopy(_cached_adapter.headers)
  headers["Authorization"] = "Bearer " .. oauth_token

  local ok, response = pcall(function()
    return curl.get(url, {
      sync = true,
      headers = headers,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get the Copilot models from " .. url .. ".\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing the response from " .. url .. ".\nError: %s", response.body)
    return {}
  end

  local models = {}
  for _, model in ipairs(json.data) do
    if model.model_picker_enabled and model.capabilities.type == "chat" then
      local choice_opts = {}

      if model.capabilities.supports.streaming then
        choice_opts.can_stream = true
      end
      if model.capabilities.supports.tool_calls then
        choice_opts.can_use_tools = true
      end
      if model.capabilities.supports.vision then
        choice_opts.has_vision = true
      end

      models[model.id] = { opts = choice_opts }
    end
  end

  _cached_models = models
  _cache_expires = utils.refresh_cache(_cache_file, config.adapters.opts.cache_models_for)

  return models
end

---Get Copilot usage statistics
---@param get_and_authorize_token_fn function Function to get and authorize token
---@param oauth_token string The oauth token
---@return table|nil
function M.get_copilot_stats(get_and_authorize_token_fn, oauth_token)
  local dummy_adapter = { url = "" }
  if not get_and_authorize_token_fn(dummy_adapter) then
    return nil
  end

  log:debug("Fetching Copilot usage statistics")

  local ok, response = pcall(function()
    return curl.get("https://api.github.com/copilot_internal/user", {
      sync = true,
      headers = {
        Authorization = "Bearer " .. oauth_token,
        Accept = "*/*",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get Copilot stats: %s", response)
    return nil
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing Copilot stats response: %s", response.body)
    return nil
  end

  return json
end

---Show Copilot usage statistics in a floating window
---@param get_and_authorize_token_fn function Function to get and authorize token
---@param oauth_token string The oauth token
---@return nil
function M.show_copilot_stats(get_and_authorize_token_fn, oauth_token)
  local stats = M.get_copilot_stats(get_and_authorize_token_fn, oauth_token)
  if not stats then
    return vim.notify("Could not retrieve Copilot stats", vim.log.levels.ERROR)
  end

  local lines = {}
  local ui = require("codecompanion.utils.ui")
  -- Progress bar for premium
  local function make_progress_bar(percent, width)
    local filled = math.floor(width * percent / 100)
    return string.rep("█", filled) .. string.rep("░", width - filled)
  end

  if stats.quota_snapshots.premium_interactions then
    local premium = stats.quota_snapshots.premium_interactions
    table.insert(lines, "##  Premium Interactions")
    local used, usage_percent = calculate_usage(premium.entitlement, premium.remaining)
    table.insert(lines, string.format("   - Used: %d / %d ", used, premium.entitlement))
    local bar = make_progress_bar(usage_percent, 20)
    table.insert(lines, string.format("     %s (%.1f%%)", bar, usage_percent))
    table.insert(lines, string.format("   - Remaining: %d", premium.remaining))
    table.insert(lines, string.format("   - Percentage: %.1f%%", premium.percent_remaining))
    if premium.unlimited then
      table.insert(lines, "   - Status: Unlimited ✨")
    else
      table.insert(lines, "   - Status: Limited")
    end
    if premium.overage_permitted then
      table.insert(lines, "   - Overage: Permitted :✔️")
    else
      table.insert(lines, "   - Overage: Not Permitted ")
    end
    table.insert(lines, "")
  end

  if stats.quota_snapshots.chat then
    local chat = stats.quota_snapshots.chat
    table.insert(lines, "## 󰭹 Chat")
    if chat.unlimited then
      table.insert(lines, "   - Status: Unlimited ✨")
    else
      local used, usage_percent = calculate_usage(premium.entitlement, premium.remaining)
      table.insert(lines, string.format("   - Used: %d / %d (%.1f%%)", used, chat.entitlement, usage_percent))
    end
    table.insert(lines, "")
  end

  if stats.quota_snapshots.completions then
    local completions = stats.quota_snapshots.completions
    table.insert(lines, "##  Completions")
    if completions.unlimited then
      table.insert(lines, "   - Status: Unlimited ✨")
    else
      local used, usage_percent = calculate_usage(premium.entitlement, premium.remaining)
      table.insert(lines, string.format("   - Used: %d / %d (%.1f%%)", used, completions.entitlement, usage_percent))
    end
  end
  if stats.quota_reset_date then
    table.insert(lines, "")
    table.insert(lines, string.format("> Quota resets on: %s", stats.quota_reset_date))
    local y, m, d = stats.quota_reset_date:match("^(%d+)%-(%d+)%-(%d+)$")
    if y and m and d then
      local days_left = (os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) }) - os.time()) / 86400
      local percent = math.max(0, math.min(((30 - days_left) / 30) * 100, 100))
      table.insert(lines, string.format("> %s (%d days left)", make_progress_bar(percent, 20), days_left))
    end
    table.insert(lines, "")
  end

  -- Create floating window
  local float_opts = {
    title = " 󰍘 Copilot Stats ",
    lock = true,
    relative = "editor",
    row = "center",
    col = "center",
    window = {
      width = 43,
      height = math.min(#lines + 2, 20),
    },
    ignore_keymaps = false,
  }
  local _, winnr = ui.create_float(lines, float_opts)

  local function get_usage_highlight(usage_percent)
    if usage_percent >= 80 then
      return "Error"
    else
      return "MoreMsg"
    end
  end
  vim.api.nvim_win_call(winnr, function()
    local premium = stats.quota_snapshots.premium_interactions
    if premium and not premium.unlimited then
      local used, usage_percent = calculate_usage(premium.entitlement, premium.remaining)
      local highlight = get_usage_highlight(usage_percent)
      vim.fn.matchadd(highlight, string.format("   - Used: %d / %d", used, premium.entitlement))
      local bar = make_progress_bar(usage_percent, PROGRESS_BAR_WIDTH)
      vim.fn.matchadd(highlight, string.format("     %s (%.1f%%)", bar, usage_percent))
    end
  end)
end

return M
