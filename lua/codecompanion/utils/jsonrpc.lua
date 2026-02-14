local M = {}

---Standard JSON-RPC error codes
M.errors = {
  PARSE = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL = -32603,
}

---Normalize empty params to encode as JSON object {} rather than array []
---@param params table|nil
---@return table
local function normalize_params(params)
  if not params then
    return vim.empty_dict()
  end
  if vim.tbl_isempty(params) then
    return vim.empty_dict()
  end
  return params
end

---Build a JSON-RPC request message
---@param id number
---@param method string
---@param params? table
---@return table
function M.request(id, method, params)
  return {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = normalize_params(params),
  }
end

---Build a JSON-RPC result response
---@param id number
---@param result any
---@return table
function M.result(id, result)
  return {
    jsonrpc = "2.0",
    id = id,
    result = result,
  }
end

---Build a JSON-RPC error response
---@param id number
---@param message string
---@param code? number Defaults to INTERNAL (-32603)
---@return table
function M.error(id, message, code)
  return {
    jsonrpc = "2.0",
    id = id,
    error = {
      code = code or M.errors.INTERNAL,
      message = message,
    },
  }
end

---Build a JSON-RPC notification (no id, no response expected)
---@param method string
---@param params? table
---@return table
function M.notification(method, params)
  return {
    jsonrpc = "2.0",
    method = method,
    params = normalize_params(params),
  }
end

---Safely decode a JSON-RPC message
---@param line string
---@param json_decode? function Decode function, defaults to vim.json.decode
---@return boolean ok
---@return table|string message_or_error
function M.decode(line, json_decode)
  json_decode = json_decode or vim.json.decode
  local ok, msg = pcall(json_decode, line)
  if not ok then
    return false, msg
  end
  if type(msg) ~= "table" then
    return false, "decoded value is not a table"
  end
  return true, msg
end

--=============================================================================
-- LineBuffer - Buffers newline-delimited stdout data
--=============================================================================

---@class CodeCompanion.JsonRPC.LineBuffer
---@field _buffer string
local LineBuffer = {}
LineBuffer.__index = LineBuffer

---Create a new line buffer
---@return CodeCompanion.JsonRPC.LineBuffer
function LineBuffer.new()
  return setmetatable({ _buffer = "" }, LineBuffer)
end

---Push data into the buffer and dispatch complete lines
---@param data string
---@param callback fun(line: string)
function LineBuffer:push(data, callback)
  if not data or data == "" then
    return
  end

  self._buffer = self._buffer .. data

  while true do
    local newline_pos = self._buffer:find("\n")
    if not newline_pos then
      break
    end

    local line = self._buffer:sub(1, newline_pos - 1):gsub("\r$", "")
    self._buffer = self._buffer:sub(newline_pos + 1)

    if line ~= "" then
      callback(line)
    end
  end
end

---Reset the buffer
function LineBuffer:reset()
  self._buffer = ""
end

M.LineBuffer = LineBuffer

--=============================================================================
-- IdGenerator - Incrementing message ID counter
--=============================================================================

---@class CodeCompanion.JsonRPC.IdGenerator
---@field _next number
local IdGenerator = {}
IdGenerator.__index = IdGenerator

---Create a new ID generator
---@param start? number Starting value (default 1)
---@return CodeCompanion.JsonRPC.IdGenerator
function IdGenerator.new(start)
  return setmetatable({ _next = start or 1 }, IdGenerator)
end

---Get the next ID
---@return number
function IdGenerator:next()
  local id = self._next
  self._next = id + 1
  return id
end

M.IdGenerator = IdGenerator

return M
