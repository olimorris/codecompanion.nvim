local hash = require("codecompanion.utils.hash")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tools.Filter
local Filter = {}

local _tool_cache = {}
local _cache_timestamp = 0
local _config_hash = nil

local CONSTANTS = {
  CACHE_TTL = 30000,
}

---Clear the enabled tools cache
---@return nil
local function clear_cache()
  _tool_cache = {}
  _cache_timestamp = 0
  _config_hash = nil
  log:trace("[Tool Filter] Cache cleared")
end

---Check if the cache is valid (time + config unchanged)
---@param tools_config_hash number The hash of the tools config
---@return boolean
local function is_cache_valid(tools_config_hash)
  local time_valid = vim.loop.now() - _cache_timestamp < CONSTANTS.CACHE_TTL
  local config_unchanged = _config_hash == tools_config_hash
  return time_valid and config_unchanged
end

---Get enabled tools from the cache or compute them
---@param tools_config table The tools configuration
---@param opts? { adapter: CodeCompanion.HTTPAdapter }
---@return table<string, boolean> Map of tool names to enabled status
local function get_enabled_tools(tools_config, opts)
  opts = opts or {}

  local current_hash = hash.hash(tools_config)
  if is_cache_valid(current_hash) and next(_tool_cache) then
    log:trace("[Tool Filter] Using cached enabled tools")
    return _tool_cache
  end

  log:trace("[Tool Filter] Computing enabled tools")
  _tool_cache = {}
  _cache_timestamp = vim.loop.now()
  _config_hash = current_hash

  for tool_name, tool_config in pairs(tools_config) do
    -- Skip special keys
    if tool_name ~= "opts" and tool_name ~= "groups" then
      local is_enabled = true

      if tool_config.enabled ~= nil then
        if type(tool_config.enabled) == "function" then
          local ok, result = pcall(tool_config.enabled, opts)
          if ok then
            is_enabled = result
          else
            log:error("[Tool Filter] Error evaluating enabled function for tool '%s': %s", tool_name, result)
            is_enabled = false
          end
        elseif type(tool_config.enabled) == "boolean" then
          is_enabled = tool_config.enabled
        end
      end

      _tool_cache[tool_name] = is_enabled
      log:trace("[Tool Filter] Tool '%s' enabled: %s", tool_name, is_enabled)
    end
  end

  return _tool_cache
end

---Filter tools configuration to only include enabled tools
---@param tools_config table The tools configuration
---@param opts? { adapter: CodeCompanion.HTTPAdapter }
---@return table The filtered tools configuration
function Filter.filter_enabled_tools(tools_config, opts)
  local enabled_tools = get_enabled_tools(tools_config, opts)
  local filtered_config = vim.deepcopy(tools_config)

  -- Remove disabled tools
  for tool_name, is_enabled in pairs(enabled_tools) do
    if not is_enabled then
      filtered_config[tool_name] = nil
      log:trace("[Tool Filter] Filtered out disabled tool: %s", tool_name)
    end
  end

  if opts and opts.adapter and opts.adapter.available_tools then
    for tool_name, tool_config in pairs(opts.adapter.available_tools) do
      local should_show = true
      if tool_config.enabled then
        if type(tool_config.enabled) == "function" then
          should_show = tool_config.enabled(opts.adapter)
        else
          should_show = tool_config.enabled
        end
      end

      -- An adapter's tool will take precedence over built-in tools
      if should_show then
        filtered_config[tool_name] = vim.tbl_extend("force", tool_config, {
          _adapter_tool = true,
          _has_client_tool = tool_config.opts and tool_config.opts.client_tool and true or false,
        })
      end
    end
  end

  -- Filter groups to only include enabled tools
  if filtered_config.groups then
    for group_name, group_config in pairs(filtered_config.groups) do
      if group_config.tools then
        local enabled_group_tools = {}
        for _, tool_name in ipairs(group_config.tools) do
          if enabled_tools[tool_name] then
            table.insert(enabled_group_tools, tool_name)
          end
        end
        filtered_config.groups[group_name].tools = enabled_group_tools

        -- Remove group if no tools are enabled
        if #enabled_group_tools == 0 then
          filtered_config.groups[group_name] = nil
          log:trace("[Tool Filter] Filtered out group with no enabled tools: %s", group_name)
        end
      end
    end
  end

  return filtered_config
end

---Check if a specific tool is enabled
---@param tool_name string The name of the tool
---@param tools_config table The tools configuration
---@return boolean
function Filter.is_tool_enabled(tool_name, tools_config)
  local enabled_tools = get_enabled_tools(tools_config)
  return enabled_tools[tool_name] == true
end

---Force the cache to refresh (useful for testing or manual refresh)
---@return nil
function Filter.refresh_cache()
  clear_cache()
  log:trace("[Tool Filter] Cache manually refreshed")
end

vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatRefreshCache",
  callback = function()
    log:trace("[Tool Filter] Cache cleared via autocommand")
    clear_cache()
  end,
})

return Filter
