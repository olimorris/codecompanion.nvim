local filter = require("codecompanion.interactions.chat.helpers.filter")
local log = require("codecompanion.utils.log")

---Add MCP tools from the MCP tools registry into the tools config
---@param tools_config table
---@return table
local function add_mcp_tools(tools_config)
  local ok, mcp = pcall(require, "codecompanion.mcp") -- Lazy load this to avoid circular dependency
  if not ok then
    return tools_config
  end
  local mcp_tools, mcp_groups = mcp.get_registered_tools()

  local merged = vim.tbl_extend("force", {}, tools_config)

  for tool_name, tool_config in pairs(mcp_tools) do
    merged[tool_name] = tool_config
  end

  if not vim.tbl_isempty(mcp_groups) then
    merged.groups = vim.tbl_extend("force", merged.groups or {}, mcp_groups)
  end

  return merged
end

---@class CodeCompanion.Tools.Filter
local Filter = filter.create_filter({
  skip_keys = { "opts", "groups" },
  pre_filter = add_mcp_tools,
  post_filter = function(filtered_cfg, opts)
    local mcp_status

    ---Determine if the MCP server for a tool has been started
    local function server_started(tool_cfg)
      local server = vim.tbl_get(tool_cfg, "opts", "_mcp_info", "server")
      if not server then
        return true
      end
      if not mcp_status then
        mcp_status = require("codecompanion.mcp").get_status()
      end
      return mcp_status[server] and mcp_status[server].started or false
    end

    -- Adapter specific tools
    if opts and opts.adapter and opts.adapter.available_tools then
      for name, cfg in pairs(opts.adapter.available_tools) do
        local should_show = true
        if cfg.enabled then
          if type(cfg.enabled) == "function" then
            should_show = cfg.enabled(opts.adapter)
          else
            should_show = cfg.enabled
          end
        end

        -- An adapter's tool will take precedence over built-in tools
        if should_show then
          filtered_cfg[name] = vim.tbl_extend("force", cfg, {
            _adapter_tool = true,
            _has_client_tool = cfg.opts and cfg.opts.client_tool and true or false,
          })
        end
      end
    end

    for name, cfg in pairs(filtered_cfg) do
      if name ~= "opts" and name ~= "groups" then
        if type(cfg) == "table" and not server_started(cfg) then
          filtered_cfg[name] = nil
          opts.enabled_items[name] = nil
          log:trace("[Tool Filter] Filtered out MCP tool for stopped server: %s", name)
        end
      end
    end

    -- Filter tool groups to only include enabled ones
    if filtered_cfg.groups then
      for name, cfg in pairs(filtered_cfg.groups) do
        if cfg.tools then
          local enabled_group_tools = {}
          for _, tool_name in ipairs(cfg.tools) do
            if opts.enabled_items[tool_name] then
              table.insert(enabled_group_tools, tool_name)
            end
          end
          filtered_cfg.groups[name].tools = enabled_group_tools

          if #enabled_group_tools == 0 then
            filtered_cfg.groups[name] = nil
            log:trace("[Tool Filter] Filtered out group with no enabled tools: %s", name)
          end
        end
      end
    end

    return filtered_cfg
  end,
})

-- Maintain backward compatibility with existing API
Filter.filter_enabled_tools = Filter.filter_enabled
Filter.is_tool_enabled = Filter.is_enabled

return Filter
