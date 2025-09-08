local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      -- Load the ACP module in child
      child.lua([[
				package.loaded['codecompanion.utils.adapters'] = {
					get_env_vars = function(a) return a end,
					set_env_vars = function(_, x) return x end,
				}

        ACP = require('codecompanion.acp')

        -- Helper to load test stubs
        function load_acp_stub(filename)
          local path = 'tests/stubs/acp/' .. filename
          local lines = vim.fn.readfile(path)
          return table.concat(lines, '\n')
        end

        -- Test adapter configuration
        test_adapter = {
          name = "test_acp",
          command = {"node", "test-acp-cli"},
          env = { GEMINI_API_KEY = "test-key" },
          defaults = {
            auth_method = "gemini-api-key",
            timeout = 2e4,
            mcpServers = {}
          },
          parameters = {
            clientCapabilities = { fs = { readTextFile = true, writeTextFile = true } },
            clientInfo = { name = "CodeCompanion.nvim", version = "1.0.0" },
            protocolVersion = 1
          },
          handlers = {
            form_messages = function(adapter, messages)
              return messages
            end
          }
        }
      ]])
    end,
    post_once = child.stop,
  },
})

T["ACP Connection"] = new_set()

T["ACP Connection"]["can create connection with adapter"] = function()
  local result = child.lua([[
    local connection = ACP.new({ adapter = test_adapter })
    return {
      has_adapter = connection.adapter ~= nil,
      adapter_name = connection.adapter.name,
      initialized = connection._initialized,
      authenticated = connection._authenticated
    }
  ]])

  h.eq(result.has_adapter, true)
  h.eq(result.adapter_name, "test_acp")
  h.eq(result.initialized, false)
  h.eq(result.authenticated, false)
end

T["ACP Connection"]["can handle real initialize response"] = function()
  child.lua([[
    -- Mock the system call and JSON responses
    local responses = {
      [1] = vim.json.decode(load_acp_stub('initialize_response.txt')),
      [2] = vim.json.decode(load_acp_stub('authenticate_response.txt')),
      [3] = vim.json.decode(load_acp_stub('session_new_response.txt'))
    }

    local mock_process = {
      write = function(data) end
    }

    -- Create connection with mocked methods
    connection = ACP.new({
      adapter = test_adapter,
      opts = {
        job = function() return mock_process end,
        schedule_wrap = function(fn) return fn end
      }
    })

    -- Simulate the connection flow
    connection._initialized = false
    connection._authenticated = false
      connection._state.handle = mock_process

      -- Test handling real initialize response
      connection:handle_rpc_message(load_acp_stub('initialize_response.txt'))
  ]])

  local result = child.lua([[
    return {
			has_response = connection.pending_responses[1] ~= nil,
      pending_count = vim.tbl_count(connection.pending_responses),
			response = connection.pending_responses[1]
    }
  ]])

  h.eq(result.has_response, true)
  h.eq(result.response[1].authMethods[2].id, "gemini-api-key")
end

T["ACP Connection"]["connect_and_initialize() end-to-end with real responses"] = function()
  local result = child.lua([[
    local init_resp = vim.json.decode(load_acp_stub('initialize_response.txt'))
    local auth_resp = vim.json.decode(load_acp_stub('authenticate_response.txt'))
    local sess_resp = vim.json.decode(load_acp_stub('session_new_response.txt'))

    local connection = ACP.new({
      adapter = test_adapter,
      opts = {
        job = function() return { write = function() end } end,
        schedule_wrap = function(fn) return fn end,
      },
    })

      -- Mock send_rpc_request to return our real responses directly
      local original_send_request = connection.send_rpc_request
      function connection:send_rpc_request(method, params)
      if method == "initialize" then
        return init_resp.result
      elseif method == "authenticate" then
        return auth_resp.result
      elseif method == "session/new" then
        return sess_resp.result
      end
      return nil
    end

      -- Skip process creation
      connection._state.handle = { write = function() end }

      -- Avoid env/command munging
      function connection:prepare_adapter()
        return test_adapter
      end

      local conn = connection:connect_and_initialize()
    return {
      ok = conn ~= nil,
      initialized = connection._initialized,
      authenticated = connection._authenticated,
      session_id = connection.session_id,
    }
  ]])

  h.eq(result.ok, true)
  h.eq(result.initialized, true)
  h.eq(result.authenticated, true)
  h.eq(result.session_id, "4fecd096-bb15-492e-a0da-95f6b9f4145a")
end

T["ACP Connection"]["skips authenticate when agent has no auth methods"] = function()
  local result = child.lua([[
    local calls = {}
    local connection = ACP.new({
      adapter = test_adapter,
      opts = {
        job = function() return { write = function() end } end,
        schedule_wrap = function(fn) return fn end,
      }
    })
      function connection:prepare_adapter() return test_adapter end
    connection._state.handle = { write = function() end }

      function connection:send_rpc_request(method, params)
      table.insert(calls, method)
      if method == "initialize" then
        return { protocolVersion = 1, authMethods = {}, agentCapabilities = { loadSession = false } }
      elseif method == "session/new" then
        return { sessionId = "sid-1" }
      end
    end

    local ok = connection:connect_and_initialize()
    return {
      ok = ok ~= nil,
      session_id = connection.session_id,
      authed = connection._authenticated,
      called = calls
    }
  ]])

  h.eq(result.ok, true)
  h.eq(result.session_id, "sid-1")
  h.eq(result.authed, true)
  h.eq(true, not vim.tbl_contains(result.called, "authenticate"))
end

T["ACP Connection"]["uses session/load when agent supports it"] = function()
  local result = child.lua([[
    local calls = {}
    local connection = ACP.new({
      adapter = test_adapter,
      opts = {
        job = function() return { write = function() end } end,
        schedule_wrap = function(fn) return fn end,
      }
    })
      function connection:prepare_adapter() return test_adapter end
    connection._state.handle = { write = function() end }
    connection.session_id = "prev-session"

      function connection:send_rpc_request(method, params)
      table.insert(calls, method)
      if method == "initialize" then
        return { protocolVersion = 1, authMethods = {}, agentCapabilities = { loadSession = true } }
      elseif method == "session/load" then
        return {} -- success
      end
    end

    local ok = connection:connect_and_initialize()
    return { ok = ok ~= nil, called = calls, session_id = connection.session_id }
  ]])

  h.eq(result.ok, true)
  h.eq(true, vim.tbl_contains(result.called, "session/load"))
  h.eq(true, not vim.tbl_contains(result.called, "session/new"))
  h.eq(result.session_id, "prev-session")
end

T["ACP Connection"]["falls back to session/new if session/load fails"] = function()
  local result = child.lua([[
    local calls = {}
    local connection = ACP.new({
      adapter = test_adapter,
      opts = {
        job = function() return { write = function() end } end,
        schedule_wrap = function(fn) return fn end,
      }
    })
      function connection:prepare_adapter() return test_adapter end
    connection._state.handle = { write = function() end }
    connection.session_id = "prev-session"

      function connection:send_rpc_request(method, params)
      table.insert(calls, method)
      if method == "initialize" then
        return { protocolVersion = 1, authMethods = {}, agentCapabilities = { loadSession = true } }
      elseif method == "session/load" then
        return nil -- simulate failure
      elseif method == "session/new" then
        return { sessionId = "new-session" }
      end
    end

    local ok = connection:connect_and_initialize()
    return { ok = ok ~= nil, called = calls, session_id = connection.session_id }
  ]])

  h.eq(result.ok, true)
  h.eq(true, vim.tbl_contains(result.called, "session/load"))
  h.eq(true, vim.tbl_contains(result.called, "session/new"))
  h.eq(result.session_id, "new-session")
end

T["ACP Responses"] = new_set()

T["ACP Responses"]["handles partial JSON messages correctly"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })

    -- Track processed messages
    local processed_messages = {}
      function connection:handle_rpc_message(line)
        table.insert(processed_messages, line)
      end

      -- Simulate partial JSON arriving in chunks
      connection:buffer_stdout_and_dispatch('{"jsonrpc":"2.0","id":1,')
      connection:buffer_stdout_and_dispatch('"result":{"test":"value"}}\n')
      connection:buffer_stdout_and_dispatch('{"jsonrpc":"2.0","id":2,"result":null}\n{"jsonrpc"')
      connection:buffer_stdout_and_dispatch(':"2.0","id":3,"result":{}}\n')

    return {
      message_count = #processed_messages,
      first_message = processed_messages[1],
      second_message = processed_messages[2],
      third_message = processed_messages[3],
    }
  ]])

  h.eq(result.message_count, 3)
  h.eq(result.first_message, '{"jsonrpc":"2.0","id":1,"result":{"test":"value"}}')
  h.eq(result.second_message, '{"jsonrpc":"2.0","id":2,"result":null}')
  h.eq(result.third_message, '{"jsonrpc":"2.0","id":3,"result":{}}')
end

T["ACP Responses"]["handles CRLF line endings in stdout"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    local processed = {}
      function connection:handle_rpc_message(line)
        table.insert(processed, line)
      end
      connection:buffer_stdout_and_dispatch('{"jsonrpc":"2.0","id":10,"result":{}}\r\n{"jsonrpc":"2.0","id":11,"result":{}}\n')
    return processed
  ]])

  h.eq(#result, 2)
  h.eq(result[1], '{"jsonrpc":"2.0","id":10,"result":{}}')
  h.eq(result[2], '{"jsonrpc":"2.0","id":11,"result":{}}')
end

T["ACP Responses"]["processes real streaming prompt responses"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })

    -- Track session updates
    local updates = {}
      connection._active_prompt = {
        handle_session_update = function(self, update)
          table.insert(updates, update)
        end
      }

    -- Read the file content and ensure final newline
    local lines = vim.fn.readfile('tests/stubs/acp/prompt_response.txt')
    local prompt_data = table.concat(lines, '\n') .. '\n'

      connection:buffer_stdout_and_dispatch(prompt_data)

    return {
      update_count = #updates,
      first_update_type = updates[1] and updates[1].sessionUpdate,
      last_update_type = updates[#updates] and updates[#updates].sessionUpdate,
      thought_chunks = vim.tbl_filter(function(u) return u.sessionUpdate == "agent_thought_chunk" end, updates),
      message_chunks = vim.tbl_filter(function(u) return u.sessionUpdate == "agent_message_chunk" end, updates),
    }
  ]])

  h.eq(result.update_count, 5)
  h.eq(result.first_update_type, "agent_thought_chunk")
  h.eq(result.last_update_type, "agent_message_chunk")
  h.eq(#result.thought_chunks, 4)
  h.eq(#result.message_chunks, 1)
  h.eq(result.message_chunks[1].content.text, "Expressive, elegant.")
end

T["ACP Responses"]["dispatches session/request_permission to active prompt"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "sess-123"
    local captured = {}
      connection._active_prompt = {
        handle_permission_request = function(_, id, params)
          captured.id = id
          captured.sid = params.sessionId
        end
      }
    local req = vim.json.encode({
      jsonrpc = "2.0",
      id = 99,
      method = "session/request_permission",
      params = { sessionId = "sess-123", options = {}, toolCall = { toolCallId = "tc1" } }
    })
      connection:buffer_stdout_and_dispatch(req .. "\r\n")
    return captured
  ]])
  h.eq(result.id, 99)
  h.eq(result.sid, "sess-123")
end

T["ACP Responses"]["_handle_done when stopReason present"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    local seen
      connection._active_prompt = {
        handle_done = function(_, sr) seen = sr end
      }
      connection:handle_rpc_message('{"jsonrpc":"2.0","id":1,"result":{"stopReason":"end_turn"}}')
    return seen
  ]])
  h.eq(result, "end_turn")
end

T["ACP Connection"]["_handle_exit resets state, calls on_exit and prompts done(canceled)"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.adapter_modified = {
      handlers = {
        on_exit = function(_, code) _G.__on_exit_code = code end
      }
    }
    local seen_done
      connection._active_prompt = {
        handle_done = function(_, sr) seen_done = sr end
      }
    connection._initialized = true
    connection._authenticated = true
    connection.session_id = "sid"
    connection.pending_responses = { x = 1 }

      connection:handle_process_exit(123, 0)

    return {
      init = connection._initialized,
      authed = connection._authenticated,
      sid = connection.session_id,
      pending = vim.tbl_count(connection.pending_responses),
      on_exit_code = _G.__on_exit_code,
      done_reason = seen_done,
    }
  ]])

  h.eq(result.init, false)
  h.eq(result.authed, false)
  h.eq(result.sid, nil)
  h.eq(result.pending, 0)
  h.eq(result.on_exit_code, 123)
  h.eq(result.done_reason, "canceled")
end

T["ACP Responses"]["fs/read_text_file and returns content"] = function()
  local result = child.lua([[
    -- Create a temp file
    local tmp = vim.fn.tempname()
    vim.fn.writefile({ "line1", "line2" }, tmp)

    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "test-session-123"

    local sent = {}
      function connection:write_message(data)
        table.insert(sent, vim.trim(data))
        return true
      end

    local req = vim.json.encode({
      jsonrpc = "2.0",
      id = 77,
      method = "fs/read_text_file",
      params = { sessionId = "test-session-123", path = tmp }
    })
      connection:buffer_stdout_and_dispatch(req .. "\n")

    local reply = vim.json.decode(sent[#sent])
    return reply
  ]])

  h.eq(result.id, 77)
  h.eq(true, result.result and type(result.result.content) == "string")
  h.eq(true, result.result.content:find("line1") ~= nil)
end

T["ACP Responses"]["fs/read_text_file ENOENT returns empty content"] = function()
  local result = child.lua([[
    package.loaded["codecompanion.strategies.chat.acp.fs"] = {
      read_text_file = function(path) return false, "ENOENT: " .. path end
    }
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "s1"
    local sent = {}
      function connection:write_message(data)
        table.insert(sent, vim.trim(data))
        return true
      end
    local req = vim.json.encode({
      jsonrpc = "2.0", id = 5, method = "fs/read_text_file",
      params = { sessionId = "s1", path = "/tmp/missing.txt" }
    })
      connection:buffer_stdout_and_dispatch(req .. "\n")
    return vim.json.decode(sent[#sent])
  ]])
  h.eq(result.id, 5)
  h.eq(result.result.content, "")
end

T["ACP Responses"]["fs/read_text_file rejects invalid sessionId"] = function()
  local result = child.lua([[
    package.loaded["codecompanion.strategies.chat.acp.fs"] = {
      read_text_file = function(path) return true, "should_not_be_called" end
    }
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "correct-session"
    local sent = {}
    function connection:write_message(data)
      table.insert(sent, vim.trim(data))
      return true
    end
    local req = vim.json.encode({
      jsonrpc = "2.0", id = 6, method = "fs/read_text_file",
      params = { sessionId = "wrong-session", path = "/tmp/x" }
    })
      connection:buffer_stdout_and_dispatch(req .. "\n")
    return vim.json.decode(sent[#sent])
  ]])

  h.eq(result.id, 6)
  h.eq(result.error.code, -32602)
end

T["ACP Responses"]["fs/write_text_file and responds with null"] = function()
  local result = child.lua([[
    -- Stub the fs module to capture writes
    local writes = {}
    package.loaded["codecompanion.strategies.chat.acp.fs"] = {
      write_text_file = function(path, content)
        table.insert(writes, { path = path, content = content })
        return true
      end
    }

    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "test-session-123"

    -- Capture what we send back to the agent
    local sent = {}
      function connection:write_message(data)
        table.insert(sent, vim.trim(data))
        return true
      end

    -- Simulate agent request
    local req = vim.json.encode({
      jsonrpc = "2.0",
      id = 42,
      method = "fs/write_text_file",
      params = {
        sessionId = "test-session-123",
        path = "/tmp/cc_write.lua",
        content = "print('ok')\n",
      }
    })
      connection:buffer_stdout_and_dispatch(req .. "\n")

    return {
      writes = writes,
      sent = vim.tbl_map(function(s) return vim.json.decode(s) end, sent),
    }
  ]])

  -- Verify the write happened and we responded result=null
  h.eq(#result.writes, 1)
  h.eq(result.writes[1].path, "/tmp/cc_write.lua")
  h.eq(result.writes[1].content, "print('ok')\n")

  h.eq(#result.sent, 1)
  h.eq(result.sent[1].id, 42)
  h.eq(result.sent[1].result, vim.NIL)
end

T["ACP Responses"]["fs/write_text_file rejects invalid sessionId"] = function()
  local result = child.lua([[
    package.loaded["codecompanion.strategies.chat.acp.fs"] = {
      write_text_file = function(path, content)
        error("should not be called for wrong session")
      end
    }

    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "correct-session"

    local sent = {}
      function connection:write_message(data)
        table.insert(sent, vim.trim(data))
        return true
      end

    local req = vim.json.encode({
      jsonrpc = "2.0",
      id = 7,
      method = "fs/write_text_file",
      params = {
        sessionId = "wrong-session",
        path = "/tmp/cc_write_bad.lua",
        content = "nope",
      }
    })
    connection:buffer_stdout_and_dispatch(req .. "\n")

    return vim.tbl_map(function(s) return vim.json.decode(s) end, sent)
  ]])

  h.eq(#result, 1)
  h.eq(result[1].id, 7)

  -- JSON-RPC error response expected
  h.eq(type(result[1].error), "table")
  h.eq(result[1].error.code, -32602)
end

T["ACP Responses"]["fs/write_text_file failure returns JSON-RPC error"] = function()
  local result = child.lua([[
    package.loaded["codecompanion.strategies.chat.acp.fs"] = {
      write_text_file = function(_) return nil, "EACCES" end
    }
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "s1"
    local sent = {}
    function connection:write_message(data)
      table.insert(sent, vim.trim(data))
      return true
    end
    local req = vim.json.encode({
      jsonrpc = "2.0", id = 8, method = "fs/write_text_file",
      params = { sessionId = "s1", path = "/root/forbidden", content = "x" }
    })
    connection:buffer_stdout_and_dispatch(req .. "\n")
    return vim.json.decode(sent[#sent])
  ]])

  h.eq(result.id, 8)
  h.eq(type(result.error), "table")
  h.is_true(result.error.message:find("fs/write_text_file failed") ~= nil)
end

T["ACP Responses"]["ignores notifications for other sessions"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })
    connection.session_id = "session-A"

    local updates = {}
    connection._active_prompt = {
      handle_session_update = function(self, u)
        table.insert(updates, u)
      end
    }

    -- Notification for a different session (should be ignored)
    local other = vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = { sessionId = "session-B", update = { sessionUpdate = "agent_message_chunk", content = { type="text", text="ignored" } } }
    })
    -- Notification for current session (should be processed)
    local ours = vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = { sessionId = "session-A", update = { sessionUpdate = "agent_message_chunk", content = { type="text", text="seen" } } }
    })

      connection:buffer_stdout_and_dispatch(other .. "\n" .. ours .. "\n")
    return { count = #updates, last = updates[#updates] and updates[#updates].content and updates[#updates].content.text }
  ]])

  h.eq(result.count, 1)
  h.eq(result.last, "seen")
end

return T
