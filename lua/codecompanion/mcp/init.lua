local Client = require("codecompanion.mcp.client")
local config = require("codecompanion.config")

local M = {}

---Return whether the server config is enabled
---@param server_cfg CodeCompanion.MCP.ServerConfig
---@return boolean
local function is_enabled(server_cfg)
  return not (server_cfg.opts and server_cfg.opts.enabled == false)
end

---@class CodeCompanion.MCP.ToolOverride
---@field opts? table
---@field enabled nil | boolean | fun(): boolean
---@field system_prompt? string
---@field output? table<string, any>
---@field timeout_ms? number

---@class CodeCompanion.MCP.ServerConfig
---@field cmd string[]
---@field env? table<string, string>
---@field opts? { enabled: boolean}
---@field server_instructions nil | string | fun(orig_server_instructions: string): string
---@field default_tool_opts? table<string, any>
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
  for name, cfg in pairs(mcp_cfg.servers) do
    if cfg.opts and cfg.opts.enabled == false then
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
---@return boolean, boolean|string
function M.enable_server(name)
  local mcp_cfg = config.mcp
  local server_cfg = mcp_cfg.servers[name]
  if not server_cfg then
    return false, string.format("MCP server not found: %s", name)
  end

  server_cfg.opts = server_cfg.opts or {}
  server_cfg.opts.enabled = true

  if not clients[name] then
    clients[name] = Client.new({ name = name, cfg = server_cfg })
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
  server_cfg.opts.enabled = false

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
---@return table<string, { ready: boolean, tool_count: number, started: boolean, enabled: boolean }>
function M.get_status()
  local status = {}

  local mcp_cfg = config.mcp
  for name, cfg in pairs(mcp_cfg.servers) do
    local client = clients[name]
    local ready = client and client.ready or false
    local tool_count = 0
    if ready then
      local tools = require("codecompanion.config").interactions.chat.tools.groups["mcp:" .. name]
      tool_count = tools and #tools.tools or 0
    end

    status[name] = {
      ready = ready,
      tool_count = tool_count,
      started = client and client.transport:started() or false,
      enabled = is_enabled(cfg),
    }
  end

  return status
end

return M
