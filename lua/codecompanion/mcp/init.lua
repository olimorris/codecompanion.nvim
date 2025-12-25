local Client = require("codecompanion.mcp.client")

local M = {}

---@class CodeCompanion.MCP.ToolOverride
---@field opts? table
---@field enabled nil | boolean | fun(): boolean
---@field system_prompt? string
---@field output? table<string, any>
---@field timeout_ms? integer

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
function M.start_all_if_not_started()
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
end

return M
