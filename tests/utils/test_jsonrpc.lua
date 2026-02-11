local h = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()
local child = MiniTest.new_child_neovim()

T["JsonRPC"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        jsonrpc = require('codecompanion.utils.jsonrpc')
      ]])
    end,
    post_once = child.stop,
  },
})

-- Message builders -------------------------------------------------------

T["JsonRPC"]["request()"] = new_set()

T["JsonRPC"]["request()"]["builds a valid request"] = function()
  local result = child.lua([[
    return jsonrpc.request(1, "initialize", { clientInfo = { name = "test" } })
  ]])

  h.eq(result.jsonrpc, "2.0")
  h.eq(result.id, 1)
  h.eq(result.method, "initialize")
  h.eq(result.params.clientInfo.name, "test")
end

T["JsonRPC"]["request()"]["uses empty dict for nil params"] = function()
  local result = child.lua([[
    local msg = jsonrpc.request(1, "ping")
    return vim.json.encode(msg)
  ]])

  -- Should encode params as {} not []
  h.eq(true, result:find('"params":{}') ~= nil)
end

T["JsonRPC"]["request()"]["uses empty dict for empty table params"] = function()
  local result = child.lua([[
    local msg = jsonrpc.request(1, "ping", {})
    return vim.json.encode(msg)
  ]])

  h.eq(true, result:find('"params":{}') ~= nil)
end

T["JsonRPC"]["result()"] = new_set()

T["JsonRPC"]["result()"]["builds a valid result response"] = function()
  local result = child.lua([[
    return jsonrpc.result(5, { sessionId = "abc" })
  ]])

  h.eq(result.jsonrpc, "2.0")
  h.eq(result.id, 5)
  h.eq(result.result.sessionId, "abc")
end

T["JsonRPC"]["error()"] = new_set()

T["JsonRPC"]["error()"]["builds error with default code"] = function()
  local result = child.lua([[
    return jsonrpc.error(3, "something failed")
  ]])

  h.eq(result.jsonrpc, "2.0")
  h.eq(result.id, 3)
  h.eq(result.error.message, "something failed")
  h.eq(result.error.code, -32603) -- INTERNAL
end

T["JsonRPC"]["error()"]["builds error with custom code"] = function()
  local result = child.lua([[
    return jsonrpc.error(3, "bad params", jsonrpc.errors.INVALID_PARAMS)
  ]])

  h.eq(result.error.code, -32602)
end

T["JsonRPC"]["notification()"] = new_set()

T["JsonRPC"]["notification()"]["builds a valid notification"] = function()
  local result = child.lua([[
    return jsonrpc.notification("session/update", { sessionId = "s1" })
  ]])

  h.eq(result.jsonrpc, "2.0")
  h.eq(result.method, "session/update")
  h.eq(result.params.sessionId, "s1")
  h.eq(result.id, nil)
end

T["JsonRPC"]["notification()"]["uses empty dict for nil params"] = function()
  local result = child.lua([[
    local msg = jsonrpc.notification("ping")
    return vim.json.encode(msg)
  ]])

  h.eq(true, result:find('"params":{}') ~= nil)
end

-- Decode -----------------------------------------------------------------

T["JsonRPC"]["decode()"] = new_set()

T["JsonRPC"]["decode()"]["decodes valid JSON-RPC message"] = function()
  local result = child.lua([[
    local ok, msg = jsonrpc.decode('{"jsonrpc":"2.0","id":1,"result":{}}')
    return { ok = ok, id = msg.id, jsonrpc = msg.jsonrpc }
  ]])

  h.eq(result.ok, true)
  h.eq(result.id, 1)
  h.eq(result.jsonrpc, "2.0")
end

T["JsonRPC"]["decode()"]["returns false for invalid JSON"] = function()
  local result = child.lua([[
    local ok, err = jsonrpc.decode('not json')
    return { ok = ok, is_string = type(err) == "string" }
  ]])

  h.eq(result.ok, false)
  h.eq(result.is_string, true)
end

T["JsonRPC"]["decode()"]["returns false for non-table result"] = function()
  local result = child.lua([[
    local ok, err = jsonrpc.decode('"just a string"')
    return { ok = ok, err = err }
  ]])

  h.eq(result.ok, false)
  h.eq(result.err, "decoded value is not a table")
end

T["JsonRPC"]["decode()"]["accepts custom decode function"] = function()
  local result = child.lua([[
    local custom = function(s) return { custom = true } end
    local ok, msg = jsonrpc.decode("anything", custom)
    return { ok = ok, custom = msg.custom }
  ]])

  h.eq(result.ok, true)
  h.eq(result.custom, true)
end

-- LineBuffer -------------------------------------------------------------

T["JsonRPC"]["LineBuffer"] = new_set()

T["JsonRPC"]["LineBuffer"]["dispatches complete lines"] = function()
  local result = child.lua([[
    local buf = jsonrpc.LineBuffer.new()
    local lines = {}
    buf:push('{"id":1}\n{"id":2}\n', function(line)
      table.insert(lines, line)
    end)
    return lines
  ]])

  h.eq(#result, 2)
  h.eq(result[1], '{"id":1}')
  h.eq(result[2], '{"id":2}')
end

T["JsonRPC"]["LineBuffer"]["buffers partial data across pushes"] = function()
  local result = child.lua([[
    local buf = jsonrpc.LineBuffer.new()
    local lines = {}
    local cb = function(line) table.insert(lines, line) end

    buf:push('{"jsonrpc":"2.0",', cb)
    buf:push('"id":1}\n', cb)

    return lines
  ]])

  h.eq(#result, 1)
  h.eq(result[1], '{"jsonrpc":"2.0","id":1}')
end

T["JsonRPC"]["LineBuffer"]["handles CRLF line endings"] = function()
  local result = child.lua([[
    local buf = jsonrpc.LineBuffer.new()
    local lines = {}
    buf:push('line1\r\nline2\n', function(line)
      table.insert(lines, line)
    end)
    return lines
  ]])

  h.eq(#result, 2)
  h.eq(result[1], "line1")
  h.eq(result[2], "line2")
end

T["JsonRPC"]["LineBuffer"]["skips empty lines"] = function()
  local result = child.lua([[
    local buf = jsonrpc.LineBuffer.new()
    local lines = {}
    buf:push('a\n\n\nb\n', function(line)
      table.insert(lines, line)
    end)
    return lines
  ]])

  h.eq(#result, 2)
  h.eq(result[1], "a")
  h.eq(result[2], "b")
end

T["JsonRPC"]["LineBuffer"]["ignores nil and empty pushes"] = function()
  local result = child.lua([[
    local buf = jsonrpc.LineBuffer.new()
    local count = 0
    local cb = function() count = count + 1 end
    buf:push(nil, cb)
    buf:push("", cb)
    return count
  ]])

  h.eq(result, 0)
end

T["JsonRPC"]["LineBuffer"]["reset clears buffer"] = function()
  local result = child.lua([[
    local buf = jsonrpc.LineBuffer.new()
    local lines = {}
    local cb = function(line) table.insert(lines, line) end

    buf:push('partial', cb)
    buf:reset()
    buf:push('fresh\n', cb)

    return lines
  ]])

  h.eq(#result, 1)
  h.eq(result[1], "fresh")
end

-- IdGenerator ------------------------------------------------------------

T["JsonRPC"]["IdGenerator"] = new_set()

T["JsonRPC"]["IdGenerator"]["starts at 1 by default"] = function()
  local result = child.lua([[
    local gen = jsonrpc.IdGenerator.new()
    return gen:next()
  ]])

  h.eq(result, 1)
end

T["JsonRPC"]["IdGenerator"]["increments on each call"] = function()
  local result = child.lua([[
    local gen = jsonrpc.IdGenerator.new()
    local a, b, c = gen:next(), gen:next(), gen:next()
    return { a, b, c }
  ]])

  h.eq(result, { 1, 2, 3 })
end

T["JsonRPC"]["IdGenerator"]["accepts custom start value"] = function()
  local result = child.lua([[
    local gen = jsonrpc.IdGenerator.new(100)
    return gen:next()
  ]])

  h.eq(result, 100)
end

-- Error constants --------------------------------------------------------

T["JsonRPC"]["errors"] = new_set()

T["JsonRPC"]["errors"]["has standard JSON-RPC error codes"] = function()
  local result = child.lua([[
    return jsonrpc.errors
  ]])

  h.eq(result.PARSE, -32700)
  h.eq(result.INVALID_REQUEST, -32600)
  h.eq(result.METHOD_NOT_FOUND, -32601)
  h.eq(result.INVALID_PARAMS, -32602)
  h.eq(result.INTERNAL, -32603)
end

return T
