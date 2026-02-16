local Client = require("codecompanion.mcp.client")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  TOOL_PREFIX = "mcp:",
}

local M = {}

---@type table<string, table> Dynamic registry for MCP tools (server_name -> { tools: table, groups: table })
local tool_registry = {}

---Automatically start the MCP server?
---@param server_cfg CodeCompanion.MCP.ServerConfig
---@return boolean
local function should_auto_start(server_cfg)
  local auto_start = server_cfg.opts and server_cfg.opts.auto_start
  if auto_start == nil then
    return config.mcp.auto_start ~= false
  end
  return auto_start ~= false
end

---Register tools from an MCP server
---@param server_name string
---@param tools table<string, table> Tool configurations keyed by tool name
---@param group table Group configuration for the server's tools
---@return nil
function M.register_tools(server_name, tools, group)
  tool_registry[server_name] = {
    tools = tools,
    group = group,
  }
end

---Unregister tools from an MCP server
---@param server_name string
---@return nil
function M.unregister_tools(server_name)
  tool_registry[server_name] = nil
end

---Get all registered MCP tools merged into a single table
---@return table<string, table> tools All MCP tools
---@return table<string, table> groups All MCP tool groups
function M.get_registered_tools()
  local all_tools = {}
  local all_groups = {}

  for server_name, registry in pairs(tool_registry) do
    for tool_name, tool_config in pairs(registry.tools) do
      all_tools[tool_name] = tool_config
    end
    if registry.group then
      all_groups[CONSTANTS.TOOL_PREFIX .. server_name] = registry.group
    end
  end

  return all_tools, all_groups
end

---Get tool count for a specific server
---@param server_name string
---@return number
function M.get_tool_count(server_name)
  local registry = tool_registry[server_name]
  if not registry then
    return 0
  end
  return vim.tbl_count(registry.tools)
end

---@class CodeCompanion.MCP.ToolOverride
---@field enabled nil | boolean | fun(): boolean
---@field output? table<string, any>
---@field opts? table
---@field system_prompt? string
---@field timeout? number

---@class CodeCompanion.MCP.ServerConfig
---@field cmd string[]
---@field env? table<string, string>
---@field opts? { auto_start?: boolean, add_to_chat?: boolean }
---@field server_instructions nil | string | fun(orig_server_instructions: string): string
---@field tool_defaults? table<string, any>
---@field tool_overrides? table<string, CodeCompanion.MCP.ToolOverride>
---@field roots? fun(): { name?: string, uri: string }[]
---@field register_roots_list_changed? fun(notify: fun())

---@class CodeCompanion.MCPConfig
---@field servers? table<string, CodeCompanion.MCP.ServerConfig>

---@type table<string, CodeCompanion.MCP.Client>
local clients = {}

---Start all configured MCP servers if not already started
---@return nil
function M.start_servers()
  local mcp_cfg = config.mcp
  if vim.tbl_isempty(mcp_cfg.servers) then
    return
  end

  local global_auto_start = mcp_cfg.auto_start

  for name, cfg in pairs(mcp_cfg.servers) do
    local auto_start = cfg.opts and cfg.opts.auto_start
    if auto_start == nil then
      auto_start = global_auto_start
    end
    if not auto_start then
      goto continue
    end
    if not clients[name] then
      local client = Client.new({ name = name, cfg = cfg })
      clients[name] = client
    end
    ::continue::
  end

  for _, client in pairs(clients) do
    client:start()
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("codecompanion.mcp.stop", { clear = true }),
    callback = function()
      pcall(function()
        M.stop_servers()
      end)
    end,
  })
end

---Stop all MCP servers
---@return nil
function M.stop_servers()
  for _, client in pairs(clients) do
    client:stop()
  end
  clients = {}
end

---Restart all MCP servers
---@return nil
function M.restart_servers()
  M.stop_servers()
  M.start_servers()
end

---Enable a configured MCP server
---@param name string
---@param opts? { on_tools_loaded?: fun() }
---@return boolean, boolean|string
function M.enable_server(name, opts)
  opts = opts or {}

  local mcp_cfg = config.mcp
  local server_cfg = mcp_cfg.servers[name]
  if not server_cfg then
    log:warn("MCP server `%s` is not configured", name)
    return false, string.format("MCP server not found: %s", name)
  end

  server_cfg.opts = server_cfg.opts or {}
  server_cfg.opts.auto_start = true

  if not clients[name] then
    clients[name] = Client.new({ name = name, cfg = server_cfg })
  end

  if opts.on_tools_loaded then
    table.insert(clients[name].on_tools_loaded, opts.on_tools_loaded)
  end

  clients[name]:start()

  return true, true
end

---Disable a configured MCP server
---@param name string
---@return boolean, boolean|string
function M.disable_server(name)
  local mcp_cfg = config.mcp
  local server_cfg = mcp_cfg.servers[name]
  if not server_cfg then
    return false, string.format("MCP server not found: %s", name)
  end

  server_cfg.opts = server_cfg.opts or {}
  server_cfg.opts.auto_start = false

  if clients[name] then
    clients[name]:stop()
    clients[name] = nil
  end

  return true, false
end

---Toggle a configured MCP server on or off
---@param name string
---@return boolean, boolean|string
function M.toggle_server(name)
  local mcp_cfg = config.mcp
  local server_cfg = mcp_cfg.servers[name]
  if not server_cfg then
    return false, string.format("MCP server not found: %s", name)
  end

  local client = clients[name]
  if client and client.transport:started() then
    return M.disable_server(name)
  end

  return M.enable_server(name)
end

---Refresh configuration and restart servers
---This allows users to update their MCP config and apply changes without restarting Neovim
---@return nil
function M.refresh()
  M.stop_servers()
  M.start_servers()
end

---Get status of all MCP servers
---@return table<string, { ready: boolean, tool_count: number, started: boolean, auto_start: boolean }>
function M.get_status()
  local status = {}

  local mcp_cfg = config.mcp
  for name, cfg in pairs(mcp_cfg.servers) do
    local client = clients[name]
    local ready = client and client.ready or false

    status[name] = {
      ready = ready,
      tool_count = M.get_tool_count(name),
      started = client and client.transport:started() or false,
      auto_start = should_auto_start(cfg),
    }
  end

  return status
end

---Cancel all pending MCP requests for a specific chat buffer
---@param chat_id number
---@param reason? string
function M.cancel_requests(chat_id, reason)
  for _, client in pairs(clients) do
    if client.ready then
      client:cancel_request_from_chat(chat_id, reason)
    end
  end
end

---Return the prefix used for MCP tools in the tool registry
---@return string
function M.tool_prefix()
  return CONSTANTS.TOOL_PREFIX
end

---Transforms the CodeCompanion MCP configuration into the format expected by an ACP adapter
---@return table
function M.transform_to_acp()
  local transformed = {}

  local add = config.mcp.add_to_chat == true

  for name, cfg in pairs(config.mcp.servers) do
    if not add and not (cfg.opts and cfg.opts.add_to_chat) then
      goto continue
    end

    table.insert(transformed, {
      name = name,
      command = cfg.cmd[1],
      args = vim.list_slice(cfg.cmd, 2),
      env = cfg.env or {},
    })

    ::continue::
  end

  return transformed
end

return M
