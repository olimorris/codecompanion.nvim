local Client = require("codecompanion.interactions.chat.mcp.client")

local M = {}

---@class CodeCompanion.MCP.ToolOverride
---@field opts? table
---@field enabled nil | boolean | fun(): boolean
---@field system_prompt? string
---@field output? table<string, any>
---@field timeout_ms? number

---@class CodeCompanion.MCP.ServerConfig
---@field cmd string[]
---@field env? table<string, string>
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
  local mcp_cfg = require("codecompanion.config").interactions.chat.mcp
  for name, cfg in pairs(mcp_cfg.servers or {}) do
    if not clients[name] then
      local client = Client:new(name, cfg)
      clients[name] = client
    end
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

---Get status of all MCP servers
---@return table<string, { ready: boolean, tool_count: number, started: boolean }>
function M.get_status()
  local status = {}

  for name, client in pairs(clients) do
    local tool_count = 0
    if client.ready then
      local tools = require("codecompanion.config").interactions.chat.tools.groups["mcp:" .. name]
      tool_count = tools and #tools.tools or 0
    end

    status[name] = {
      ready = client.ready,
      tool_count = tool_count,
      started = client.transport:started(),
    }
  end

  return status
end

return M
