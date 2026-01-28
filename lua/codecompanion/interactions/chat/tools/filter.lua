local filter = require("codecompanion.interactions.chat.helpers.filter")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tools.Filter
local Filter = filter.create_filter({
  skip_keys = { "opts", "groups" },
  post_filter = function(filtered_config, opts, enabled_items)
    local mcp_status
    local function is_mcp_tool_started(tool_cfg)
      local server = vim.tbl_get(tool_cfg, "opts", "_mcp_info", "server")
      if not server then
        return true
      end
      if not mcp_status then
        mcp_status = require("codecompanion.mcp").get_status()
      end
      return mcp_status[server] and mcp_status[server].started or false
    end

    -- Adapter specific tool
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

    for tool_name, tool_config in pairs(filtered_config) do
      if tool_name ~= "opts" and tool_name ~= "groups" then
        if type(tool_config) == "table" and not is_mcp_tool_started(tool_config) then
          filtered_config[tool_name] = nil
          enabled_items[tool_name] = nil
          log:trace("[Tool Filter] Filtered out MCP tool for stopped server: %s", tool_name)
        end
      end
    end

    -- Filter tool groups to only include enabled ones
    if filtered_config.groups then
      for group_name, group_config in pairs(filtered_config.groups) do
        if group_config.tools then
          local enabled_group_tools = {}
          for _, tool_name in ipairs(group_config.tools) do
            if enabled_items[tool_name] then
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
  end,
})

-- Maintain backward compatibility with existing API
Filter.filter_enabled_tools = Filter.filter_enabled
Filter.is_tool_enabled = Filter.is_enabled

return Filter
