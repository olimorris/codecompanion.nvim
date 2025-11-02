local hash = require("codecompanion.utils.hash")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.SlashCommands.Filter
local Filter = {}

local _slash_command_cache = {}
local _cache_timestamp = 0
local _config_hash = nil

local CONSTANTS = {
  CACHE_TTL = 30000,
}

---Clear the enabled slash commands cache
---@return nil
local function clear_cache()
  _slash_command_cache = {}
  _cache_timestamp = 0
  _config_hash = nil
  log:trace("[Slash Command Filter] Cache cleared")
end

---Check if the cache is valid (time + config unchanged)
---@param config_hash number The hash of the slash commands config
---@return boolean
local function is_cache_valid(config_hash)
  local time_valid = vim.loop.now() - _cache_timestamp < CONSTANTS.CACHE_TTL
  local config_unchanged = _config_hash == config_hash
  return time_valid and config_unchanged
end

---Get enabled slash commands from the cache or compute them
---@param slash_commands_config table The slash commands configuration
---@param opts? { adapter: table }
---@return table<string, boolean> Map of slash command names to enabled status
local function get_enabled_slash_commands(slash_commands_config, opts)
  opts = opts or {}

  local current_hash = hash.hash(slash_commands_config)
  if is_cache_valid(current_hash) and next(_slash_command_cache) then
    log:trace("[Slash Command Filter] Using cached enabled slash commands")
    return _slash_command_cache
  end

  log:trace("[Slash Command Filter] Computing enabled slash commands")
  _slash_command_cache = {}
  _cache_timestamp = vim.loop.now()
  _config_hash = current_hash

  for cmd_name, cmd_config in pairs(slash_commands_config) do
    -- Skip special keys
    if cmd_name ~= "opts" then
      local is_enabled = true

      if cmd_config.enabled ~= nil then
        if type(cmd_config.enabled) == "function" then
          local ok, result = pcall(cmd_config.enabled, opts)
          if ok then
            is_enabled = result
          else
            log:error("[Slash Command Filter] Error evaluating enabled function for command '%s': %s", cmd_name, result)
            is_enabled = false
          end
        elseif type(cmd_config.enabled) == "boolean" then
          is_enabled = cmd_config.enabled
        end
      end

      _slash_command_cache[cmd_name] = is_enabled
      log:trace("[Slash Command Filter] Slash command '%s' enabled: %s", cmd_name, is_enabled)
    end
  end

  return _slash_command_cache
end

---Filter slash commands configuration to only include enabled slash commands
---@param slash_commands_config table The slash commands configuration
---@param opts? { adapter: table }
---@return table The filtered slash commands configuration
function Filter.filter_enabled_slash_commands(slash_commands_config, opts)
  local enabled_slash_commands = get_enabled_slash_commands(slash_commands_config, opts)
  local filtered_config = vim.deepcopy(slash_commands_config)

  -- Remove disabled slash commands
  for cmd_name, is_enabled in pairs(enabled_slash_commands) do
    if not is_enabled then
      filtered_config[cmd_name] = nil
      log:trace("[Slash Command Filter] Filtered out disabled slash command: %s", cmd_name)
    end
  end

  return filtered_config
end

---Check if a specific slash command is enabled
---@param cmd_name string The name of the slash command
---@param slash_commands_config table The slash commands configuration
---@param opts? { adapter: table }
---@return boolean
function Filter.is_slash_command_enabled(cmd_name, slash_commands_config, opts)
  local enabled_slash_commands = get_enabled_slash_commands(slash_commands_config, opts)
  return enabled_slash_commands[cmd_name] == true
end

---Force the cache to refresh (useful for testing or manual refresh)
---@return nil
function Filter.refresh_cache()
  clear_cache()
  log:trace("[Slash Command Filter] Cache manually refreshed")
end

vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatRefreshCache",
  callback = function()
    log:trace("[Slash Command Filter] Cache cleared via autocommand")
    clear_cache()
  end,
})

return Filter
