local h = require("tests.helpers")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

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
        jobstart = function() return mock_process end,
        schedule_wrap = function(fn) return fn end
      }
    })

    -- Simulate the connection flow
    connection._initialized = false
    connection._authenticated = false
    connection.process.handle = mock_process

    -- Test handling real initialize response
    connection:_handle_message(load_acp_stub('initialize_response.txt'))
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

T["ACP Connection"]["connect() end-to-end with real responses"] = function()
  local result = child.lua([[
    local init_resp = vim.json.decode(load_acp_stub('initialize_response.txt'))
    local auth_resp = vim.json.decode(load_acp_stub('authenticate_response.txt'))
    local sess_resp = vim.json.decode(load_acp_stub('session_new_response.txt'))

    local connection = ACP.new({
      adapter = test_adapter,
      opts = {
        jobstart = function() return { write = function() end } end,
        schedule_wrap = function(fn) return fn end,
      },
    })

    -- Mock _send_request to return our real responses directly
    local original_send_request = connection._send_request
    function connection:_send_request(method, params)
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
    connection.process.handle = { write = function() end }

    -- Avoid env/command munging
    function connection:_setup_adapter()
      return test_adapter
    end

    local conn = connection:connect()
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

T["ACP Responses"] = new_set()

T["ACP Responses"]["handles partial JSON messages correctly"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })

    -- Track processed messages
    local processed_messages = {}
    function connection:_handle_message(line)
      table.insert(processed_messages, line)
    end

    -- Simulate partial JSON arriving in chunks
    connection:_handle_stdout('{"jsonrpc":"2.0","id":1,')
    connection:_handle_stdout('"result":{"test":"value"}}\n')
    connection:_handle_stdout('{"jsonrpc":"2.0","id":2,"result":null}\n{"jsonrpc"')
    connection:_handle_stdout(':"2.0","id":3,"result":{}}\n')

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

T["ACP Responses"]["processes real streaming prompt responses"] = function()
  local result = child.lua([[
    local connection = ACP.new({
      adapter = test_adapter,
      opts = { schedule_wrap = function(fn) return fn end }
    })

    -- Track session updates
    local updates = {}
    connection._active_prompt = {
      _handle_session_update = function(self, update)
        table.insert(updates, update)
      end
    }

    -- Read the file content and ensure final newline
    local lines = vim.fn.readfile('tests/stubs/acp/prompt_response.txt')
    local prompt_data = table.concat(lines, '\n') .. '\n'

    connection:_handle_stdout(prompt_data)

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

T["ACP Responses"]["PromptBuilder"] = function()
  local result = child.lua([[
    local connection = ACP.new({ adapter = test_adapter })
    connection.session_id = "test-session-123"
    connection.process = { next_id = 10 }
    connection.methods = { encode = vim.json.encode }

    -- Track handler calls and sent data
    local handler_calls = {}
    local sent_data = ""

    connection._send_data = function(self, data)
      sent_data = data
      return true
    end

    -- Create prompt with fluent API
    local prompt = connection:prompt({
      { role = "user", content = "Test message" }
    })
    :on_message_chunk(function(content)
      table.insert(handler_calls, { type = "message", content = content })
    end)
    :on_thought_chunk(function(content)
      table.insert(handler_calls, { type = "thought", content = content })
    end)
    :on_complete(function(reason)
      table.insert(handler_calls, { type = "complete", reason = reason })
    end)
    :with_options({ silent = true })

    -- Send and simulate responses
    local job = prompt:send()
    prompt:_handle_session_update({
      sessionUpdate = "agent_thought_chunk",
      content = { text = "Thinking..." }
    })
    prompt:_handle_session_update({
      sessionUpdate = "agent_message_chunk",
      content = { text = "Hello!" }
    })
    prompt:_handle_done()

    return {
      handler_count = #handler_calls,
      thought_call = handler_calls[1],
      message_call = handler_calls[2],
      complete_call = handler_calls[3],
      has_shutdown = type(job.shutdown) == "function",
      sent_request = vim.json.decode(vim.trim(sent_data)),
    }
  ]])

  h.eq(result.handler_count, 3)
  h.eq(result.thought_call.type, "thought")
  h.eq(result.thought_call.content, "Thinking...")
  h.eq(result.message_call.type, "message")
  h.eq(result.message_call.content, "Hello!")
  h.eq(result.complete_call.type, "complete")
  h.eq(result.has_shutdown, true)
  h.eq(result.sent_request.method, "session/prompt")
  h.eq(result.sent_request.params.sessionId, "test-session-123")
end

return T
