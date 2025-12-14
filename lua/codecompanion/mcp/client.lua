---MCP Client implementation
local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")
local tool_bridge = require("codecompanion.mcp.tool_bridge")
local utils = require("codecompanion.utils")

-- We set a large but fixed limit on tools per server to avoid infinite pagination loops
local MAX_TOOLS_PER_SERVER = 100

local JsonRpc = {
  ERROR_PARSE = -32700,
  ERROR_INVALID_REQUEST = -32600,
  ERROR_METHOD_NOT_FOUND = -32601,
  ERROR_INVALID_PARAMS = -32602,
  ERROR_INTERNAL = -32603,
}

local last_msg_id = 0
local function next_msg_id()
  last_msg_id = last_msg_id + 1
  return last_msg_id
end

---Abstraction over the IO connection to a MCP server
---@class CodeCompanion.MCP.Connection
---@field start fun(self: CodeCompanion.MCP.Connection, on_line_read: fun(line: string), on_close: fun(err: string?))
---@field started fun(self: CodeCompanion.MCP.Connection): boolean
---@field write fun(self: CodeCompanion.MCP.Connection, lines: string[]?)

---Default Connection implementation backed by vim.system
---@class CodeCompanion.MCP.StdioConnection : CodeCompanion.MCP.Connection
---@field name string
---@field cmd string[]
---@field env table?
---@field _proc vim.SystemObj?
---@field _last_tail string?
---@field _on_line_read fun(line: string)?
---@field _on_close fun(err: string?)?
local StdioConnection = {}
StdioConnection.__index = StdioConnection

---@params name string
---@params cfg CodeCompanion.MCP.ServerConfig
function StdioConnection:new(name, cfg)
  return setmetatable({
    name = name,
    cmd = cfg.cmd,
    env = cfg.env,
  }, self)
end

function StdioConnection:start(on_line_read, on_close)
  assert(not self._proc, "StdioConnection: start called when already started")
  self._on_line_read = on_line_read
  self._on_close = on_close

  adapter_utils.get_env_vars(self)
  self._proc = vim.system(
    self.cmd,
    {
      env = self.env_replaced or self.env,
      text = true,
      stdin = true,
      stdout = vim.schedule_wrap(function(err, data)
        self:_handle_stdout(err, data)
      end),
      stderr = vim.schedule_wrap(function(err, data)
        self:_handle_stderr(err, data)
      end),
    },
    vim.schedule_wrap(function(out)
      self:_handle_exit(out)
    end)
  )
end

function StdioConnection:started()
  return self._proc ~= nil
end

function StdioConnection:_handle_stdout(err, data)
  if err then
    log:error("StdioConnection stdout error: %s", err)
    return
  end
  if not data or data == "" then
    return
  end

  local combined = ""
  if self._last_tail then
    combined = self._last_tail .. data
    self._last_tail = nil
  else
    combined = data
  end

  local last_newline_pos = combined:match(".*()\n")
  if last_newline_pos == nil then
    self._last_tail = combined
    return
  elseif last_newline_pos < #combined then
    self._last_tail = combined:sub(last_newline_pos + 1)
    combined = combined:sub(1, last_newline_pos)
  end

  for line in vim.gsplit(combined, "\n", { plain = true, trimempty = true }) do
    if line ~= "" and self._on_line_read then
      local ok, _ = pcall(self._on_line_read, line)
      if not ok then
        log:error("StdioConnection on_line_read callback failed for line: %s", line)
      end
    end
  end
end

function StdioConnection:_handle_stderr(err, data)
  if err then
    log:error("StdioConnection stderr error: %s", err)
    return
  end
  if data then
    log:info("[MCP.%s] stderr: %s", self.name, data)
  end
end

function StdioConnection:_handle_exit(out)
  local err_msg = nil
  if out and (out.code ~= 0) then
    err_msg = string.format("exit code %s, signal %s", tostring(out.code), tostring(out.signal))
  end
  self._proc = nil
  if self._on_close then
    local ok, _ = pcall(self._on_close, err_msg)
    if not ok then
      log:error("StdioConnection on_close callback failed")
    end
  end
end

function StdioConnection:write(lines)
  if not self._proc then
    error("StdioConnection: write called before start")
  end
  self._proc:write(lines)
end

---@alias ServerRequestHandler fun(cli: CodeCompanion.MCP.Client, params: table<string, any>?): "result" | "error", table<string, any>
---@alias ResponseHandler fun(resp: MCP.JSONRPCResultResponse|MCP.JSONRPCErrorResponse)

---@class CodeCompanion.MCP.Client
---@field name string
---@field cfg CodeCompanion.MCP.ServerConfig
---@field ready boolean
---@field connection CodeCompanion.MCP.Connection
---@field resp_handlers table<integer, ResponseHandler>
---@field server_request_handlers table<string, ServerRequestHandler>
---@field server_capabilities table<string, any>?
---@field server_instructions string?
local Client = {
  _conn_factory = function(name, cfg)
    return StdioConnection:new(name, cfg)
  end,
}
Client.__index = Client

---@param name string
---@param cfg CodeCompanion.MCP.ServerConfig
function Client:new(name, cfg)
  return setmetatable({
    name = name,
    cfg = cfg,
    ready = false,
    connection = self._conn_factory(name, cfg),
    resp_handlers = {},
    server_request_handlers = {
      ["ping"] = self._handle_server_ping,
      ["roots/list"] = self._handler_server_roots_list,
    },
  }, self)
end

function Client:start_if_not_started()
  if self.connection:started() then
    return
  end
  log:info("[MCP.%s] Starting with command: %s", self.name, table.concat(self.cfg.cmd, " "))

  self.connection:start(function(line)
    self:_on_conn_line_read(line)
  end, function(err)
    self:_on_conn_close(err)
  end)
  utils.fire("MCPServerStart", { name = self.name })

  self:_start_init_mcp()
end

function Client:_start_init_mcp()
  assert(self.connection:started(), "MCP Server process is not running.")
  assert(not self.ready, "MCP Server is already initialized.")

  local capabilities = vim.empty_dict()
  if self.cfg.roots then
    capabilities.roots = { listChanged = self.cfg.register_roots_list_changed ~= nil }
  end

  self:request("initialize", {
    protocolVersion = "2025-11-25",
    clientInfo = {
      name = "CodeCompanion.nvim",
      version = "NO VERSION", --MCP Spec explicitly requires a version
    },
    capabilities = capabilities,
  }, function(resp)
    if resp.error then
      log:error("[MCP.%s] initialization failed: %s", self.name, vim.inspect(resp))

      return
    end
    log:info("[MCP.%s] initialized successfully.", self.name)
    log:info("[MCP.%s] protocol version: %s", self.name, resp.result.protocolVersion)
    log:info("[MCP.%s] info: %s", self.name, vim.inspect(resp.result.serverInfo))
    log:info("[MCP.%s] capabilities: %s", self.name, vim.inspect(resp.result.capabilities))
    self:notify("notifications/initialized")
    self.server_capabilities = resp.result.capabilities
    self.server_instructions = resp.result.instructions
    self.ready = true
    if self.cfg.register_roots_list_changed then
      self.cfg.register_roots_list_changed(function()
        self:notify_roots_list_changed()
      end)
    end
    utils.fire("MCPServerReady", { name = self.name })
    self:refresh_tools()
  end)
end

function Client:_on_conn_close(err)
  self.ready = false
  if not err then
    log:info("[MCP.%s] exited.", self.name)
  else
    log:warn("[MCP.%s] exited with error: %s", self.name, err)
  end
  utils.fire("MCPServerExit", { name = self.name, err = err })
end

function Client:_on_conn_line_read(line)
  if not line or line == "" then
    return
  end
  local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true } })
  if not ok then
    log:error("[MCP.%s] failed to decode received line [%s]: %s", self.name, msg, line)
    return
  end
  if type(msg) ~= "table" or msg.jsonrpc ~= "2.0" then
    log:error("[MCP.%s] received invalid MCP message: %s", self.name, line)
    return
  end
  if msg.id == nil then
    log:info("[MCP.%s] received notification: %s", self.name, line)
    return
  end

  if msg.method then
    self:_handle_server_request(msg)
  else
    local handler = self.resp_handlers[msg.id]
    if handler then
      self.resp_handlers[msg.id] = nil
      local handle_ok, handle_result = pcall(handler, msg)
      if handle_ok then
        log:debug("[MCP.%s] response handler succeeded for request %s", self.name, msg.id)
      else
        log:error("[MCP.%s] response handler failed for request %s: %s", self.name, msg.id, handle_result)
      end
    else
      log:warn("[MCP.%s] received response with unknown id %s: %s", self.name, msg.id, line)
    end
  end
end

---@param msg MCP.JSONRPCRequest
function Client:_handle_server_request(msg)
  assert(self.connection:started(), "MCP Server process is not running.")
  local resp = {
    jsonrpc = "2.0",
    id = msg.id,
  }
  local handler = self.server_request_handlers[msg.method]
  if not handler then
    log:warn("[MCP.%s] received request %s with unknown method %s", self.name, msg.id, msg.method)
    resp.error = { code = JsonRpc.ERROR_METHOD_NOT_FOUND, message = "Method not found" }
  else
    local ok, status, body = pcall(handler, self, msg.params)
    if not ok then
      log:error("[MCP.%s] handler for method %s failed for request %s: %s", self.name, msg.method, msg.id, status)
      resp.error = { code = JsonRpc.ERROR_INTERNAL, message = status }
    elseif status == "error" then
      log:error(
        "[MCP.%s] handler for method %s returned error for request %s: %s",
        self.name,
        msg.method,
        msg.id,
        vim.inspect(body)
      )
      resp.error = body
    elseif status == "result" then
      log:debug("[MCP.%s] handler for method %s returned result for request %s", self.name, msg.method, msg.id)
      resp.result = body
    else
      log:error(
        "[MCP.%s] handler for method %s returned invalid status %s for request %s",
        self.name,
        msg.method,
        status,
        msg.id
      )
      resp.error = { code = JsonRpc.ERROR_INTERNAL, message = "Internal server error" }
    end
  end
  local resp_str = vim.json.encode(resp)
  self.connection:write({ resp_str })
end

function Client:notify(method, params)
  assert(self.connection:started(), "MCP Server process is not running.")
  if params and vim.tbl_isempty(params) then
    params = vim.empty_dict()
  end
  local notif = {
    jsonrpc = "2.0",
    method = method,
    params = params,
  }
  local notif_str = vim.json.encode(notif)
  log:debug("[MCP.%s] sending notification: %s", self.name, notif_str)
  self.connection:write({ notif_str })
end

---@param method string
---@param params table<string, any>?
---@param resp_handler ResponseHandler
---@param opts table? { timeout_ms: integer? }
---@return integer req_id
function Client:request(method, params, resp_handler, opts)
  assert(self.connection:started(), "MCP Server process is not running.")
  local req_id = next_msg_id()
  if params and vim.tbl_isempty(params) then
    params = vim.empty_dict()
  end
  local req = {
    jsonrpc = "2.0",
    id = req_id,
    method = method,
    params = params,
  }
  if resp_handler then
    self.resp_handlers[req_id] = resp_handler
  end
  local req_str = vim.json.encode(req)
  log:debug("[MCP.%s] sending request %s: %s", self.name, req_id, req_str)
  self.connection:write({ req_str })

  local timeout_ms = opts and opts.timeout_ms
  if timeout_ms then
    vim.defer_fn(function()
      if self.resp_handlers[req_id] then
        self.resp_handlers[req_id] = nil
        self:cancel_request(req_id, "timeout")
        local timeout_msg = string.format("Request timeout after %dms", timeout_ms)
        if resp_handler then
          local ok, _ = pcall(resp_handler, {
            jsonrpc = "2.0",
            id = req_id,
            error = { code = JsonRpc.ERROR_INTERNAL, message = timeout_msg },
          })
          if not ok then
            log:error("[MCP.%s] response handler failed to handle timeout for request %s", self.name, req_id)
          end
        end
      end
    end, timeout_ms)
  end

  return req_id
end

function Client:_handle_server_ping(params)
  return "result", {}
end

function Client:_handler_server_roots_list(params)
  if not self.cfg.roots then
    return "error", { code = JsonRpc.ERROR_METHOD_NOT_FOUND, message = "roots capability not enabled" }
  end

  local ok, roots = pcall(self.cfg.roots)
  if not ok then
    log:error("[MCP.%s] roots function failed: %s", self.name, roots)
    return "error", { code = JsonRpc.ERROR_INTERNAL, message = "roots function failed" }
  end

  if not roots or type(roots) ~= "table" then
    log:error("[MCP.%s] roots function returned invalid result: %s", self.name, vim.inspect(roots))
    return "error", { code = JsonRpc.ERROR_INTERNAL, message = "roots function returned invalid result" }
  end

  return "result", { roots = roots }
end

function Client:notify_roots_list_changed()
  self:notify("notifications/roots/list_changed")
end

---Cancel a pending request to the MCP server
---@param req_id integer The ID of the request to cancel
---@param reason string? The reason for cancellation
function Client:cancel_request(req_id, reason)
  log:info("[MCP.%s] cancelling request %s: %s", self.name, req_id, reason or "<no reason>")
  self.resp_handlers[req_id] = nil
  self:notify("notifications/cancelled", {
    requestId = req_id,
    reason = reason,
  })
end

---Call a tool on the MCP server
---@param name string The name of the tool to call
---@param args table<string, any> The arguments to pass to the tool
---@param callback fun(ok: boolean, result_or_error: MCP.CallToolResult | string) Callback function that receives (ok, result_or_error)
---@param opts table? { timeout_ms: integer? }
---@return integer req_id
function Client:call_tool(name, args, callback, opts)
  assert(self.ready, "MCP Server is not ready.")

  return self:request("tools/call", {
    name = name,
    arguments = args,
  }, function(resp)
    if resp.error then
      log:error("[MCP.%s] call_tool request failed for [%s]: %s", self.name, name, vim.inspect(resp))
      callback(false, string.format("MCP JSONRPC error: [%s] %s", resp.error.code, resp.error.message))
      return
    end

    callback(true, resp.result)
  end, opts)
end

function Client:refresh_tools()
  assert(self.ready, "MCP Server is not ready.")
  if not self.server_capabilities.tools then
    log:warn("[MCP.%s] does not support tools", self.name)
    return
  end

  local all_tools = {} ---@type MCP.Tool[]
  local function load_tools(cursor)
    self:request("tools/list", { cursor = cursor }, function(resp)
      if resp.error then
        log:error("[MCP.%s] tools/list request failed: %s", self.name, vim.inspect(resp))
        return
      end

      local tools = resp.result and resp.result.tools or {}
      for _, tool in ipairs(tools) do
        log:info("[MCP.%s] provides tool [%s]: %s", self.name, tool.name, tool.title or "<NO TITLE>")
        table.insert(all_tools, tool)
      end

      -- pagination handling
      local next_cursor = resp.result and resp.result.nextCursor
      if next_cursor and #tools >= MAX_TOOLS_PER_SERVER then
        log:warn("[MCP.%s] returned too many tools (%d), stop further loading", self.name, #tools)
      elseif next_cursor then
        log:info("[MCP.%s] loading more tools with cursor: %s", self.name, next_cursor)
        return load_tools(next_cursor)
      end

      -- install tools into CodeCompanion
      local installed_tools = tool_bridge.install_tools(self, all_tools)
      utils.fire("MCPToolsLoaded", { server = self.name, tools = installed_tools })
    end)
  end

  load_tools()
end

return Client
