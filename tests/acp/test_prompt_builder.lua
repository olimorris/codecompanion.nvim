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

T["Prompt Builder"] = new_set()

T["Prompt Builder"]["PromptBuilder"] = function()
  local result = child.lua([[
    local connection = ACP.new({ adapter = test_adapter })
    connection.session_id = "test-session-123"
    connection.process = { next_id = 10 }
    connection.methods = { encode = vim.json.encode }

    -- Track handler calls and sent data
    local handler_calls = {}
    local sent_data = ""

    connection._write_to_process = function(self, data)
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
      content = { type = "text", text = "Thinking..." }
    })
    prompt:_handle_session_update({
      sessionUpdate = "agent_message_chunk",
      content = { type = "text", text = "Hello!" }
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

T["Prompt Builder"]["extracts text safely from non-text content"] = function()
  local result = child.lua([[
    local connection = ACP.new({ adapter = test_adapter })
    connection.session_id = "test-session-123"

    local seen = {}
    local prompt = connection:prompt({ { role = "user", content = "hi" } })
      :on_message_chunk(function(text) table.insert(seen, text) end)
      :on_thought_chunk(function(text) table.insert(seen, "T:" .. text) end)

    -- Simulate image and resource_link chunks
    prompt:_handle_session_update({
      sessionUpdate = "agent_message_chunk",
      content = { type = "image", data = "..." }
    })
    prompt:_handle_session_update({
      sessionUpdate = "agent_message_chunk",
      content = { type = "resource_link", uri = "file:///tmp/x.txt", name = "x" }
    })
    prompt:_handle_session_update({
      sessionUpdate = "agent_thought_chunk",
      content = { type = "text", text = "thinking" }
    })

    return seen
  ]])

  -- Expect placeholders for image/resource_link and proper text for thought
  h.eq(result[1], "[image]")
  h.eq(true, result[2]:match("^%[resource: ") ~= nil)
  h.eq(result[3], "T:thinking")
end

T["Prompt Builder"]["cancel sends notification (no id)"] = function()
  local result = child.lua([[
    local connection = ACP.new({ adapter = test_adapter })
    connection.session_id = "test-session-123"
    connection.methods = { encode = vim.json.encode }
    connection._state = { next_id = 1 } -- ensure state

    local sent = {}
    connection._write_to_process = function(self, data)
      table.insert(sent, vim.trim(data))
      return true
    end

    local prompt = connection:prompt({ { role = "user", content = "hi" } })
    prompt:cancel()

    local obj = vim.json.decode(sent[#sent])
    return { has_id = obj.id ~= nil, method = obj.method, params = obj.params }
  ]])

  h.eq(result.has_id, false)
  h.eq(result.method, "session/cancel")
  h.eq(result.params.sessionId, "test-session-123")
end

T["Prompt Builder"]["Sends selected outcome response"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")

    local adapter = {
      handlers = { form_messages = function(_, msgs) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local conn = Connection.new({ adapter = adapter })
    conn.session_id = "test-session-2"

    _G.captured = nil
    conn._write_to_process = function(self, data)
      _G.captured = data
      return true
    end

    local pb = conn:prompt({ { type = "text", text = "hi" } })

    pb:on_permission_request(function(req)
      req.respond("opt-2", false)
    end)

    local params = {
      sessionId = "sess-2",
      options = {
        { optionId = "opt-1", name = "Always allow", kind = "allow_always" },
        { optionId = "opt-2", name = "Allow once",   kind = "allow_once"   },
      },
      toolCall = {
        toolCallId = "tc-2",
        status = "pending",
        title = "Execute",
        content = {},
        kind = "execute",
      },
    }

    pb:_handle_permission_request(7, params)

    local sent = vim.json.decode(_G.captured or "{}")
    return {
      id = sent.id,
      outcome = sent.result and sent.result.outcome and sent.result.outcome.outcome or nil,
      optionId = sent.result and sent.result.outcome and sent.result.outcome.optionId or nil,
    }
  ]])

  h.eq(7, result.id)
  h.eq("selected", result.outcome)
  h.eq("opt-2", result.optionId)
end

T["Prompt Builder"]["Auto-cancels when no handler is registered"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")

    local adapter = {
      handlers = { form_messages = function(_, msgs) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local conn = Connection.new({ adapter = adapter })
    conn.session_id = "test-session-3"

    _G.captured = nil
    conn._write_to_process = function(self, data)
      _G.captured = data
      return true
    end

    local pb = conn:prompt({ { type = "text", text = "hello" } })

    local params = {
      sessionId = "sess-3",
      options = {
        { optionId = "opt-1", name = "Allow", kind = "allow_once" },
      },
      toolCall = {
        toolCallId = "tc-3",
        status = "pending",
        title = "Edit file",
        content = {},
        kind = "edit",
      },
    }

    pb:_handle_permission_request(13, params)

    local sent = vim.json.decode(_G.captured or "{}")
    return {
      id = sent.id,
      outcome = sent.result and sent.result.outcome and sent.result.outcome.outcome or nil,
      has_optionId = sent.result and sent.result.outcome and sent.result.outcome.optionId ~= nil,
    }
  ]])

  h.eq(13, result.id)
  h.eq("canceled", result.outcome)
  h.eq(false, result.has_optionId)
end

return T
