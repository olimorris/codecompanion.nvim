local hash = require("codecompanion.utils.hash")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  CACHE_TTL = 30000,
}

---@class CodeCompanion.Filter
local Filter = {}

---Create a new filter instance
---@param filter_type string The type of filter (e.g., "tool", "slash_command")
---@param config table Configuration with optional custom logic
---@return table The filter module
function Filter.create_filter(filter_type, config)
  config = config or {}

  local Filter = {}
  local _cache = {}
  local _cache_timestamp = 0
  local _config_hash = nil

  ---Clear the cache
  ---@return nil
  local function clear_cache()
    _cache = {}
    _cache_timestamp = 0
    _config_hash = nil
    log:trace("[%s Filter] Cache cleared", filter_type)
  end

  ---Check if the cache is valid (time + config unchanged)
  ---@param config_hash number The hash of the config
  ---@return boolean
  local function is_cache_valid(config_hash)
    local time_valid = vim.loop.now() - _cache_timestamp < CONSTANTS.CACHE_TTL
    local config_unchanged = _config_hash == config_hash
    return time_valid and config_unchanged
  end

  ---Evaluate if an item should be enabled
  ---@param item_config table The item configuration
  ---@param opts table Options passed to the enabled function
  ---@return boolean
  local function evaluate_enabled(item_config, opts)
    local is_enabled = true

    if item_config.enabled ~= nil then
      if type(item_config.enabled) == "function" then
        local ok, result = pcall(item_config.enabled, opts)
        if ok then
          is_enabled = result
        else
          log:error("[%s Filter] Error evaluating enabled function: %s", filter_type, result)
          is_enabled = false
        end
      elseif type(item_config.enabled) == "boolean" then
        is_enabled = item_config.enabled
      end
    end

    return is_enabled
  end

  ---Get enabled items from the cache or compute them
  ---@param items_config table The items configuration
  ---@param opts? table Options to pass to enabled functions
  ---@return table<string, boolean> Map of item names to enabled status
  local function get_enabled_items(items_config, opts)
    opts = opts or {}

    local current_hash = hash.hash(items_config)
    if is_cache_valid(current_hash) and next(_cache) then
      log:trace("[%s Filter] Using cached enabled items", filter_type)
      return _cache
    end

    log:trace("[%s Filter] Computing enabled items", filter_type)
    _cache = {}
    _cache_timestamp = vim.loop.now()
    _config_hash = current_hash

    -- Get skip keys from config or use defaults
    local skip_keys = config.skip_keys or { "opts" }

    for item_name, item_config in pairs(items_config) do
      -- Skip special keys
      local should_skip = false
      for _, skip_key in ipairs(skip_keys) do
        if item_name == skip_key then
          should_skip = true
          break
        end
      end

      if not should_skip then
        local is_enabled = evaluate_enabled(item_config, opts)
        _cache[item_name] = is_enabled
        log:trace("[%s Filter] Item '%s' enabled: %s", filter_type, item_name, is_enabled)
      end
    end

    return _cache
  end

  ---Filter configuration to only include enabled items
  ---@param items_config table The items configuration
  ---@param opts? table Options to pass to enabled functions
  ---@return table The filtered configuration
  function Filter.filter_enabled(items_config, opts)
    local enabled_items = get_enabled_items(items_config, opts)
    local filtered_config = vim.deepcopy(items_config)

    -- Remove disabled items
    for item_name, is_enabled in pairs(enabled_items) do
      if not is_enabled then
        filtered_config[item_name] = nil
        log:trace("[%s Filter] Filtered out disabled item: %s", filter_type, item_name)
      end
    end

    -- Run custom post-filter logic if provided
    if config.post_filter then
      filtered_config = config.post_filter(filtered_config, opts, enabled_items)
    end

    return filtered_config
  end

  ---Check if a specific item is enabled
  ---@param item_name string The name of the item
  ---@param items_config table The items configuration
  ---@param opts? table Options to pass to enabled functions
  ---@return boolean
  function Filter.is_enabled(item_name, items_config, opts)
    local enabled_items = get_enabled_items(items_config, opts)
    return enabled_items[item_name] == true
  end

  ---Force the cache to refresh
  ---@return nil
  function Filter.refresh_cache()
    clear_cache()
    log:trace("[%s Filter] Cache manually refreshed", filter_type)
  end

  -- Set up autocmd for cache refresh
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatRefreshCache",
    callback = function()
      log:trace("[%s Filter] Cache cleared via autocommand", filter_type)
      clear_cache()
    end,
  })

  return Filter
end

return Filter
