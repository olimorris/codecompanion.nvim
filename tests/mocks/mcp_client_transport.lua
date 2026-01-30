local log = require("codecompanion.utils.log")

---A mock implementation of `Transport`
---@class CodeCompanion.MCP.MockMCPClientTransport : CodeCompanion.MCP.Transport
---@field private _started boolean
---@field private _on_line_read? fun(line: string)
---@field private _on_close? fun()
---@field private _line_handlers (fun(line: string): boolean)[]
local MockMCPClientTransport = {}
MockMCPClientTransport.__index = MockMCPClientTransport

function MockMCPClientTransport:new()
  return setmetatable({
    _started = false,
    _line_handlers = {},
  }, self)
end

function MockMCPClientTransport:start(on_line_read, on_close)
  assert(not self._started, "Transport already started")
  self._on_line_read = on_line_read
  self._on_close = on_close
  self._started = true
end

function MockMCPClientTransport:started()
  return self._started
end

function MockMCPClientTransport:write(lines)
  assert(self._started, "Transport not started")
  if lines == nil then
    self:stop()
    return
  end
  vim.schedule(function()
    for _, line in ipairs(lines) do
      log:info("MockMCPClientTransport received line: %s", line)
      assert(#self._line_handlers > 0, "No pending line handlers")
      local handler = self._line_handlers[1]
      local keep = handler(line)
      if not keep then
        table.remove(self._line_handlers, 1)
      end
    end
  end)
end

function MockMCPClientTransport:write_line_to_client(line, latency)
  assert(self._started, "Transport not started")
  vim.defer_fn(function()
    log:info("MockMCPClientTransport sending line to client: %s", line)
    self._on_line_read(line)
  end, latency or 0)
end

---@param handler fun(line: string): boolean handle a client written line; return true to preserve this handler for next line
---@return CodeCompanion.MCP.MockMCPClientTransport self
function MockMCPClientTransport:expect_client_write_line(handler)
  table.insert(self._line_handlers, handler)
  return self
end

---@param method string
---@param handler fun(params?: table): "result"|"error", table
---@param opts? { repeats?: integer, latency?: integer }
---@return CodeCompanion.MCP.MockMCPClientTransport self
function MockMCPClientTransport:expect_jsonrpc_call(method, handler, opts)
  local remaining_repeats = opts and opts.repeats or 1
  return self:expect_client_write_line(function(line)
    local function get_response()
      local resp = { jsonrpc = "2.0" }
      local ok, req = pcall(vim.json.decode, line, { luanil = { object = true } })
      if not ok then
        resp.error = { code = -32700, message = string.format("Parse error: %s", req) }
        return resp
      end
      resp.id = req.id
      if req.jsonrpc ~= "2.0" then
        resp.error = { code = -32600, message = string.format("Invalid JSON-RPC version: %s", req.jsonrpc) }
        return resp
      end
      if req.method ~= method then
        resp.error = { code = -32601, message = string.format("Expected method '%s', got '%s'", method, req.method) }
        return resp
      end
      local status, result = handler(req.params)
      if status == "result" then
        resp.result = result
      elseif status == "error" then
        resp.error = result
      else
        error("Handler must return 'result' or 'error'")
      end
      return resp
    end

    self:write_line_to_client(vim.json.encode(get_response()), opts and opts.latency)
    remaining_repeats = remaining_repeats - 1
    return remaining_repeats > 0
  end)
end

---@param method string
---@param handler? fun(params?: table)
---@param opts? { repeats: integer }
---@return CodeCompanion.MCP.MockMCPClientTransport self
function MockMCPClientTransport:expect_jsonrpc_notify(method, handler, opts)
  local remaining_repeats = opts and opts.repeats or 1
  return self:expect_client_write_line(function(line)
    local ok, req = pcall(vim.json.decode, line, { luanil = { object = true } })
    if not ok then
      log:error("Failed to parse JSON-RPC notification: %s", line)
    elseif req.jsonrpc ~= "2.0" then
      log:error("Invalid JSON-RPC version: %s", req.jsonrpc)
    elseif req.method ~= method then
      log:error("Unexpected JSON-RPC method. Expected: %s, Got: %s", method, req.method)
    elseif handler then
      handler(req.params)
    end
    remaining_repeats = remaining_repeats - 1
    return remaining_repeats > 0
  end)
end

---@param method string
---@param params? table<string, any>
---@param resp_handler fun(status: "result"|"error", result_or_error: table)
function MockMCPClientTransport:send_request_to_client(method, params, resp_handler)
  assert(self:all_handlers_consumed(), "Cannot send request to client: pending line handlers exist")
  local req_id = math.random(1, 1e9)
  local req = { jsonrpc = "2.0", id = req_id, method = method, params = params }
  self:expect_client_write_line(function(line)
    local ok, resp = pcall(vim.json.decode, line, { luanil = { object = true } })
    if not ok then
      log:error("Failed to parse JSON-RPC response: %s", line)
    elseif resp.id ~= req_id then
      log:error("Mismatched JSON-RPC response ID. Expected: %d, Got: %s", req_id, tostring(resp.id))
    elseif resp.result then
      resp_handler("result", resp.result)
    elseif resp.error then
      resp_handler("error", resp.error)
    else
      log:error("Invalid JSON-RPC response: %s", line)
    end
    return false
  end)
  self:write_line_to_client(vim.json.encode(req))
end

function MockMCPClientTransport:all_handlers_consumed()
  return #self._line_handlers == 0
end

function MockMCPClientTransport:stop()
  vim.schedule(function()
    self._started = false
    self._on_close()
  end)
end

function MockMCPClientTransport:expect_transport_stop()
  return self:expect_client_write_line(function(line)
    assert(line == nil, "Expected transport to be stopped")
    return false
  end)
end

return MockMCPClientTransport
