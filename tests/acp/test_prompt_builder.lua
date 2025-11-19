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

        agent_info = {
          agentCapabilities = {
            loadSession = false,
            promptCapabilities = {
              audio = true,
              embeddedContext = true,
              image = true
            }
          },
          authMethods = { {
              description = vim.NIL,
              id = "oauth-personal",
              name = "Log in with Google"
            }, {
              description = "Requires setting the `GEMINI_API_KEY` environment variable",
              id = "gemini-api-key",
              name = "Use Gemini API key"
            }, {
              description = vim.NIL,
              id = "vertex-ai",
              name = "Vertex AI"
            } },
          protocolVersion = 1
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
    connection._agent_info = agent_info

    -- Track handler calls and sent data
    local handler_calls = {}
    local sent_data = ""

    connection.write_message = function(self, data)
      sent_data = data
      return true
    end

    -- Create prompt with fluent API
    local prompt = connection:session_prompt({
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
    prompt:handle_session_update({
      sessionUpdate = "agent_thought_chunk",
      content = { type = "text", text = "Thinking..." }
    })
    prompt:handle_session_update({
      sessionUpdate = "agent_message_chunk",
      content = { type = "text", text = "Hello!" }
    })
    prompt:handle_done()

    return {
      handler_count = #handler_calls,
      thought_call = handler_calls[1],
      message_call = handler_calls[2],
      complete_call = handler_calls[3],
      has_cancel = type(job.cancel) == "function",
      sent_request = vim.json.decode(vim.trim(sent_data)),
    }
  ]])

  h.eq(result.handler_count, 3)
  h.eq(result.thought_call.type, "thought")
  h.eq(result.thought_call.content, "Thinking...")
  h.eq(result.message_call.type, "message")
  h.eq(result.message_call.content, "Hello!")
  h.eq(result.complete_call.type, "complete")
  h.eq(result.has_cancel, true)
  h.eq(result.sent_request.method, "session/prompt")
  h.eq(result.sent_request.params.sessionId, "test-session-123")
end

T["Prompt Builder"]["extracts text safely from non-text content"] = function()
  local result = child.lua([[
    local connection = ACP.new({ adapter = test_adapter })
    connection.session_id = "test-session-123"
    connection._agent_info = agent_info

    local seen = {}
    local prompt = connection:session_prompt({ { role = "user", content = "hi" } })
      :on_message_chunk(function(text) table.insert(seen, text) end)
      :on_thought_chunk(function(text) table.insert(seen, "T:" .. text) end)

    -- Simulate image and resource_link chunks
    prompt:handle_session_update({
      sessionUpdate = "agent_message_chunk",
      content = { type = "image", data = "..." }
    })
    prompt:handle_session_update({
      sessionUpdate = "agent_message_chunk",
      content = { type = "resource_link", uri = "file:///tmp/x.txt", name = "x" }
    })
    prompt:handle_session_update({
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
    connection._agent_info = agent_info

    local sent = {}
    connection.write_message = function(self, data)
      table.insert(sent, vim.trim(data))
      return true
    end

    local prompt = connection:session_prompt({ { role = "user", content = "hi" } })
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
      handlers = { form_messages = function(_, msgs, capabilities) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local connection = Connection.new({ adapter = adapter })
    connection.session_id = "test-session-2"
    connection._agent_info = agent_info

    _G.captured = nil
    connection.write_message = function(self, data)
      _G.captured = data
      return true
    end

    local pb = connection:session_prompt({ { type = "text", text = "hi" } })

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

    pb:handle_permission_request(7, params)

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

    local connection = Connection.new({ adapter = adapter })
    connection.session_id = "test-session-3"
    connection._agent_info = agent_info

    _G.captured = nil
    connection.write_message = function(self, data)
      _G.captured = data
      return true
    end

    local pb = connection:session_prompt({ { type = "text", text = "hello" } })

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

    pb:handle_permission_request(13, params)

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

T["Prompt Builder"]["handle_error calls error handler and fires event"] = function()
  local result = child.lua([[
    local error_handler_called = false
    local error_msg = nil
    local events_fired = {}

    -- Mock utils.fire to capture events BEFORE loading modules
    package.loaded["codecompanion.utils"] = {
      fire = function(event, data)
        table.insert(events_fired, { event = event, data = data })
      end,
      capitalize = function(s) return s end,
    }

    -- Force reload of ACP modules to pick up mocked utils
    package.loaded["codecompanion.acp.prompt_builder"] = nil
    package.loaded["codecompanion.acp"] = nil

    local Connection = require("codecompanion.acp")

    local adapter = {
      handlers = { form_messages = function(_, msgs) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local connection = Connection.new({ adapter = adapter })
    connection.session_id = "test-session-4"
    connection._agent_info = agent_info

    local pb = connection:session_prompt({ { type = "text", text = "test" } })
      :on_error(function(msg)
        error_handler_called = true
        error_msg = msg
      end)
      :with_options({ bufnr = 1, strategy = "chat" })

    -- Simulate error - pass error message as string
    pb:handle_error("LLM provider error: quota exceeded")

    return {
      error_handler_called = error_handler_called,
      error_msg = error_msg,
      event_count = #events_fired,
      last_event = events_fired[#events_fired],
    }
  ]])

  h.eq(result.error_handler_called, true)
  h.eq(result.error_msg, "LLM provider error: quota exceeded")
  h.eq(result.event_count, 1)
  h.eq(result.last_event.event, "RequestFinished")
  h.eq(result.last_event.data.status, "error")
  h.eq(result.last_event.data.error, "LLM provider error: quota exceeded")
end

T["Prompt Builder"]["handle_error accepts error object with message field"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")

    local adapter = {
      handlers = { form_messages = function(_, msgs) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local connection = Connection.new({ adapter = adapter })
    connection.session_id = "test-session-5"
    connection._agent_info = agent_info

    local captured_msg = nil

    local pb = connection:session_prompt({ { type = "text", text = "test" } })
      :on_error(function(msg)
        captured_msg = msg
      end)
      :with_options({ silent = true })

    -- Simulate error with error object (backward compatibility)
    pb:handle_error({
      code = -32603,
      message = "LLM provider error: Error code: 429 - account suspended"
    })

    return captured_msg
  ]])

  h.eq(result, "LLM provider error: Error code: 429 - account suspended")
end

return T
