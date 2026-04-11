local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[h = require('tests.helpers')]])
    end,
    pre_case = function()
      child.lua([[
        -- Mock ACP connection for chat integration tests
        _G.mock_acp_connection = {
          _config_options = {},
          connected = false,
          session_id = nil,

          connect_and_authenticate = function(self)
            self.connected = true
            return self
          end,

          ensure_session = function(self)
            self.session_id = "test-session-123"
            return true
          end,

          session_prompt = function(self, messages)
            return {
              messages = messages,
              handlers = {},
              options = {},

              on_message_chunk = function(self, handler)
                self.handlers.message_chunk = handler
                return self
              end,

              on_thought_chunk = function(self, handler)
                self.handlers.thought_chunk = handler
                return self
              end,

              on_tool_call = function(self, handler)
                self.handlers.tool_call = handler
                return self
              end,

              on_tool_update = function(self, handler)
                self.handlers.tool_update = handler
                return self
              end,

              on_permission_request = function(self, handler)
                self.handlers.permission_request = handler
                return self
              end,

              on_complete = function(self, handler)
                self.handlers.complete = handler
                return self
              end,

              on_error = function(self, handler)
                self.handlers.error = handler
                return self
              end,

              with_options = function(self, opts)
                self.options = opts
                return self
              end,

              send = function(self)
                -- Store for verification, don't actually send
                _G.last_prompt_request = self
                return { shutdown = function() end }
              end
            }
          end,

          disconnect = function(self)
            self.connected = false
            self.session_id = nil
          end,

          get_config_options = function(self)
            return self._config_options or {}
          end,

          get_models = function(self)
            return nil
          end
        }
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.mock_acp_connection = nil
        _G.last_prompt_request = nil
        _G.last_permission_request = nil
        _G.codecompanion_chat_metadata = nil

        -- Reset modules that tests may have overridden
        package.loaded["codecompanion.acp"] = nil
        package.loaded["codecompanion.interactions.chat.acp.request_permission"] = nil
        package.loaded["codecompanion.interactions.chat.acp.handler"] = nil
        package.loaded["codecompanion.interactions.chat.acp.commands"] = nil
        package.loaded["codecompanion.interactions.chat"] = nil
        package.loaded["codecompanion.config"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["ACPHandler"] = new_set()

T["ACPHandler"]["establishes connection when needed"] = function()
  local result = child.lua([[
    -- Create chat with ACP adapter
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = {
          form_messages = function(adapter, messages)
            return vim.tbl_map(function(msg)
              return { type = "text", text = msg.content }
            end, messages)
          end
        }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Mock the ACP client to return our mock connection
    package.loaded["codecompanion.acp"] = {
      new = function(args)
        return _G.mock_acp_connection
      end
    }

    -- Submit should establish connection
    local request = handler:submit({
      messages = {{ type = "text", text = "Hello" }}
    })

    return {
      has_connection = chat.acp_connection ~= nil,
      connection_established = chat.acp_connection.connected,
      session_id = chat.acp_connection.session_id,
      request_sent = _G.last_prompt_request ~= nil
    }
  ]])

  h.is_true(result.has_connection)
  h.is_true(result.connection_established)
  h.eq("test-session-123", result.session_id)
  h.is_true(result.request_sent)
end

T["ACPHandler"]["handles streaming message chunks"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Track what gets added to the buffer
    local buffer_messages = {}
    chat.add_buf_message = function(self, data, opts)
      table.insert(buffer_messages, { data = data, opts = opts })
    end

    -- Simulate message chunk handling
    handler:handle_message_chunk("Hello ")
    handler:handle_message_chunk("there!")

    return {
      message_count = #buffer_messages,
      first_content = buffer_messages[1].data.content,
      second_content = buffer_messages[2].data.content,
      message_type = buffer_messages[1].opts.type
    }
  ]])

  h.eq(2, result.message_count)
  h.eq("Hello ", result.first_content)
  h.eq("there!", result.second_content)
  h.eq("llm_message", result.message_type)
end

T["ACPHandler"]["handles thought chunks"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    local buffer_messages = {}
    chat.add_buf_message = function(self, data, opts)
      table.insert(buffer_messages, { data = data, opts = opts })
    end

    -- Simulate thought chunk handling
    handler:handle_thought_chunk("Let me think about this...")
    handler:handle_thought_chunk("I need to consider...")

    return {
      message_count = #buffer_messages,
      first_content = buffer_messages[1].data.content,
      message_type = buffer_messages[1].opts.type,
      reasoning_collected = #handler.reasoning
    }
  ]])

  h.eq(2, result.message_count)
  h.eq("Let me think about this...", result.first_content)
  h.eq("reasoning_message", result.message_type)
  h.eq(2, result.reasoning_collected)
end

T["ACPHandler"]["suppresses thought chunks when show_reasoning is false"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({
      display = {
        chat = {
          show_reasoning = false
        }
      }
    }, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    local buffer_messages = {}
    chat.add_buf_message = function(self, data, opts)
      table.insert(buffer_messages, { data = data, opts = opts })
    end

    handler:handle_thought_chunk("Let me think about this...")
    handler:handle_thought_chunk("I need to consider...")

    return {
      message_count = #buffer_messages,
      reasoning_collected = #handler.reasoning
    }
  ]])

  h.eq(0, result.message_count)
  h.eq(2, result.reasoning_collected)
end

T["ACPHandler"]["coordinates completion flow"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Track completion calls
    local completion_data = {}
    chat.done = function(self, output, reasoning, tools)
      completion_data = { output = output, reasoning = reasoning, tools = tools }
    end

    -- Simulate full interaction
    handler:handle_message_chunk("Response part 1")
    handler:handle_message_chunk(" and part 2")
    handler:handle_thought_chunk("My reasoning")
    handler:handle_complete("end_turn")

    return {
      status = chat.status,
      final_output = completion_data.output,
      final_reasoning = completion_data.reasoning,
      final_tools = completion_data.tools
    }
  ]])

  h.eq("success", result.status)
  h.eq({ "Response part 1", " and part 2" }, result.final_output)
  h.eq({ "My reasoning" }, result.final_reasoning)
  h.eq({}, result.final_tools)
end

T["ACPHandler"]["handles connection errors"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Mock connection failure
    package.loaded["codecompanion.acp"] = {
      new = function(args)
        return {
          connect_and_authenticate = function() return nil end -- Connection fails
        }
      end
    }

    local completion_called = false
    chat.done = function(self, output)
      completion_called = true
    end

    local request = handler:submit({
      messages = {{ type = "text", text = "Hello" }}
    })

    return {
      status = chat.status,
      completion_called = completion_called,
      request_returned = request
    }
  ]])

  h.eq("error", result.status)
  h.is_true(result.completion_called)
  h.eq(nil, result.request_returned)
end

T["ACPHandler"]["integrates with chat submit flow"] = function()
  local result = child.lua([[
    -- Create chat with ACP adapter
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    -- Mock the ACP connection
    package.loaded["codecompanion.acp"] = {
      new = function(args)
        return _G.mock_acp_connection
      end
    }

    -- Add a user message to submit
    chat:add_message({
      role = "user",
      content = "Test ACP submission"
    })

    -- Track the submission
    local submitted_payload = nil
    local original_submit_acp = chat._submit_acp
    chat._submit_acp = function(self, payload)
      submitted_payload = payload
      return original_submit_acp(self, payload)
    end

    -- Submit the chat - this should use ACP pathway
    chat:submit()

    return {
      adapter_type = chat.adapter.type,
      payload_submitted = submitted_payload ~= nil,
      has_messages = submitted_payload and #submitted_payload.messages > 0,
      last_prompt_set = _G.last_prompt_request ~= nil
    }
  ]])

  h.eq("acp", result.adapter_type)
  h.is_true(result.payload_submitted)
  h.is_true(result.has_messages)
  h.is_true(result.last_prompt_set)
end

T["ACPHandler"]["hydrates permission request with cached diff tool_call"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Pre-populate cache with a diff tool call
    local id = "toolu_abc123"
    handler.tools[id] = {
      toolCallId = id,
      kind = "edit",
      status = "pending",
      title = "Edit `/tmp/file.txt`",
      content = {
        { type = "diff", path = "/tmp/file.txt", oldText = "old", newText = "new" }
      },
    }

    -- Stub the permission UI to capture the request
    _G.last_permission_request = nil
    package.loaded["codecompanion.interactions.chat.acp.request_permission"] = {
      confirm = function(chat_arg, request)
        _G.last_permission_request = request
      end
    }

    -- Simulate a permission request that only includes toolCallId
    handler:handle_permission_request({
      tool_call = { toolCallId = id },
      options = {
        { kind = "allow_once", optionId = "allow", name = "Allow" },
        { kind = "reject_once", optionId = "reject", name = "Reject" },
      }
    })

    local req = _G.last_permission_request
    return {
      hydrated = req ~= nil and req.tool_call ~= nil and req.tool_call.content ~= nil,
      toolCallId = req and req.tool_call and req.tool_call.toolCallId or nil,
      diff_type = req and req.tool_call and req.tool_call.content and req.tool_call.content[1] and req.tool_call.content[1].type or nil,
      newText = req and req.tool_call and req.tool_call.content and req.tool_call.content[1] and req.tool_call.content[1].newText or nil,
    }
  ]])

  h.is_true(result.hydrated)
  h.eq("toolu_abc123", result.toolCallId)
  h.eq("diff", result.diff_type)
  h.eq("new", result.newText)
end

T["ACPHandler"]["permission request passes through when toolCallId unknown"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Stub the permission UI to capture the request
    _G.last_permission_request = nil
    package.loaded["codecompanion.interactions.chat.acp.request_permission"] = {
      confirm = function(chat_arg, request)
        _G.last_permission_request = request
      end
    }

    -- Simulate a permission request that references an unknown toolCallId
    handler:handle_permission_request({
      tool_call = { toolCallId = "unknown_tool_id" },
      options = {
        { kind = "allow_once", optionId = "allow", name = "Allow" },
        { kind = "reject_once", optionId = "reject", name = "Reject" },
      }
    })

    local req = _G.last_permission_request
    return {
      has_request = req ~= nil,
      has_tool_call = req and req.tool_call ~= nil,
      has_content = req and req.tool_call and req.tool_call.content ~= nil,
      toolCallId = req and req.tool_call and req.tool_call.toolCallId or nil,
    }
  ]])

  h.is_true(result.has_request)
  h.is_true(result.has_tool_call)
  h.is_false(result.has_content)
  h.eq("unknown_tool_id", result.toolCallId)
end

T["ACPHandler"]["transforms ACP commands in messages"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Setup mock connection with session
    chat.acp_connection = {
      session_id = "test-session-123"
    }

    -- Register available ACP commands
    local commands = require("codecompanion.interactions.chat.acp.commands")
    commands.register_commands("test-session-123", {
      { name = "cost", description = "Show costs" },
      { name = "context", description = "Manage context" },
    })

    -- Test transformation
    local messages = {
      { content = "\\cost" },
      { content = "\\context --detailed" },
      { content = "Regular text with \\backslash" },
      { content = "\\cost at end" },
    }

    local transformed = handler:transform_acp_commands(messages)

    return {
      first = transformed[1].content,
      second = transformed[2].content,
      third = transformed[3].content,
      fourth = transformed[4].content,
    }
  ]])

  h.eq("/cost", result.first)
  h.eq("/context --detailed", result.second)
  h.eq("Regular text with \\backslash", result.third) -- Unknown command not transformed
  h.eq("/cost at end", result.fourth)
end

T["ACPHandler"]["only transforms known ACP commands"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    chat.acp_connection = {
      session_id = "test-session-456"
    }

    -- Register only 'cost' command
    local commands = require("codecompanion.interactions.chat.acp.commands")
    commands.register_commands("test-session-456", {
      { name = "cost", description = "Show costs" },
    })

    local messages = {
      { content = "\\cost is known" },
      { content = "\\unknown is not" },
    }

    local transformed = handler:transform_acp_commands(messages)

    return {
      first = transformed[1].content,
      second = transformed[2].content,
    }
  ]])

  h.eq("/cost is known", result.first)
  h.eq("\\unknown is not", result.second) -- Unknown command preserved
end

T["ACPHandler"]["handles no registered commands"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    chat.acp_connection = {
      session_id = "test-session-789"
    }

    -- No commands registered for this session

    local messages = {
      { content = "\\cost should not transform" },
    }

    local transformed = handler:transform_acp_commands(messages)

    return {
      content = transformed[1].content,
    }
  ]])

  h.eq("\\cost should not transform", result.content)
end

T["ACPHandler"]["handles no connection"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- No connection established

    local messages = {
      { content = "\\cost" },
    }

    local transformed = handler:transform_acp_commands(messages)

    return {
      content = transformed[1].content,
    }
  ]])

  h.eq("\\cost", result.content)
end

T["ACPHandler"]["Permission Queue"] = new_set()

T["ACPHandler"]["Permission Queue"]["queues concurrent requests and presents one at a time"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    -- Track which requests reach the permission UI
    local confirmed = {}
    package.loaded["codecompanion.interactions.chat.acp.request_permission"] = {
      confirm = function(chat_arg, request)
        table.insert(confirmed, request)
      end
    }

    -- Send three permission requests concurrently
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_1", kind = "edit", title = "Edit file A" },
      options = { { kind = "allow_once", optionId = "allow", name = "Allow" } },
      respond = function() end,
    })
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_2", kind = "edit", title = "Edit file B" },
      options = { { kind = "allow_once", optionId = "allow", name = "Allow" } },
      respond = function() end,
    })
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_3", kind = "edit", title = "Edit file C" },
      options = { { kind = "allow_once", optionId = "allow", name = "Allow" } },
      respond = function() end,
    })

    return {
      confirmed_count = #confirmed,
      first_id = confirmed[1] and confirmed[1].tool_call.toolCallId,
      queue_count = handler._permission.queue:count(),
      active = handler._permission.active,
    }
  ]])

  h.eq(1, result.confirmed_count)
  h.eq("tool_1", result.first_id)
  h.eq(2, result.queue_count)
  h.is_true(result.active)
end

T["ACPHandler"]["Permission Queue"]["presents next request after user responds"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    local confirmed = {}
    package.loaded["codecompanion.interactions.chat.acp.request_permission"] = {
      confirm = function(chat_arg, request)
        table.insert(confirmed, request)
      end
    }

    local responses = {}
    local make_respond = function(id)
      return function(option_id, canceled)
        table.insert(responses, { id = id, option_id = option_id, canceled = canceled })
      end
    end

    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_1" },
      options = { { kind = "allow_once", optionId = "allow", name = "Allow" } },
      respond = make_respond("tool_1"),
    })
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_2" },
      options = { { kind = "allow_once", optionId = "allow", name = "Allow" } },
      respond = make_respond("tool_2"),
    })

    -- Simulate user accepting the first request
    confirmed[1].respond("allow", false)

    return {
      confirmed_count = #confirmed,
      second_id = confirmed[2] and confirmed[2].tool_call.toolCallId,
      responses = responses,
      queue_empty = handler._permission.queue:is_empty(),
      active = handler._permission.active,
    }
  ]])

  h.eq(2, result.confirmed_count)
  h.eq("tool_2", result.second_id)
  h.eq("tool_1", result.responses[1].id)
  h.eq("allow", result.responses[1].option_id)
  h.is_true(result.queue_empty)
  h.is_true(result.active)
end

T["ACPHandler"]["Permission Queue"]["clears queue on completion"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    local confirmed = {}
    package.loaded["codecompanion.interactions.chat.acp.request_permission"] = {
      confirm = function(chat_arg, request)
        table.insert(confirmed, request)
      end
    }

    local rejected = {}
    local make_respond = function(id)
      return function(option_id, canceled)
        if canceled then
          table.insert(rejected, id)
        end
      end
    end

    -- Queue up three requests
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_1" },
      options = {},
      respond = make_respond("tool_1"),
    })
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_2" },
      options = {},
      respond = make_respond("tool_2"),
    })
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_3" },
      options = {},
      respond = make_respond("tool_3"),
    })

    -- Simulate completion while requests are still queued
    chat.done = function() end
    handler:handle_complete()

    return {
      queue_empty = handler._permission.queue:is_empty(),
      active = handler._permission.active,
      rejected = rejected,
    }
  ]])

  h.is_true(result.queue_empty)
  h.is_false(result.active)
  h.eq({ "tool_2", "tool_3" }, result.rejected)
end

T["ACPHandler"]["Permission Queue"]["clears queue on error"] = function()
  local result = child.lua([[
    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    local confirmed = {}
    package.loaded["codecompanion.interactions.chat.acp.request_permission"] = {
      confirm = function(chat_arg, request)
        table.insert(confirmed, request)
      end
    }

    local rejected = {}
    local make_respond = function(id)
      return function(option_id, canceled)
        if canceled then
          table.insert(rejected, id)
        end
      end
    end

    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_1" },
      options = {},
      respond = make_respond("tool_1"),
    })
    handler:handle_permission_request({
      tool_call = { toolCallId = "tool_2" },
      options = {},
      respond = make_respond("tool_2"),
    })

    -- Stub add_buf_message and done
    chat.add_buf_message = function() end
    chat.done = function() end
    handler:handle_error("Something went wrong")

    return {
      queue_empty = handler._permission.queue:is_empty(),
      active = handler._permission.active,
      rejected = rejected,
    }
  ]])

  h.is_true(result.queue_empty)
  h.is_false(result.active)
  h.eq({ "tool_2" }, result.rejected)
end

T["ACPHandler"]["Config Options"] = new_set()

T["ACPHandler"]["Config Options"]["updates metadata with config options"] = function()
  local result = child.lua([[
    local mock_connection = vim.deepcopy(_G.mock_acp_connection)
    mock_connection._config_options = {
      {
        type = "select",
        id = "mode",
        name = "Mode",
        category = "mode",
        currentValue = "plan",
        options = {
          { value = "default", name = "Always Ask" },
          { value = "plan", name = "Plan Mode" },
        },
      },
    }
    mock_connection.get_config_options = function(self)
      return self._config_options
    end

    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    chat.acp_connection = mock_connection
    chat:update_metadata()

    local metadata = _G.codecompanion_chat_metadata[chat.bufnr]

    return {
      has_config_options = metadata.config_options ~= nil,
      mode_current = metadata.config_options and metadata.config_options.mode and metadata.config_options.mode.current,
      mode_name = metadata.config_options and metadata.config_options.mode and metadata.config_options.mode.name,
    }
  ]])

  h.is_true(result.has_config_options)
  h.eq("plan", result.mode_current)
  h.eq("Plan Mode", result.mode_name)
end

T["ACPHandler"]["Config Options"]["handles no config options gracefully"] = function()
  local result = child.lua([[
    local mock_connection = vim.deepcopy(_G.mock_acp_connection)
    mock_connection._config_options = {}
    mock_connection.get_config_options = function(self)
      return self._config_options
    end

    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    chat.acp_connection = mock_connection
    chat:update_metadata()

    local metadata = _G.codecompanion_chat_metadata[chat.bufnr]

    return {
      metadata_exists = metadata ~= nil,
      has_config_options = metadata.config_options ~= nil,
    }
  ]])

  h.is_true(result.metadata_exists)
  h.is_false(result.has_config_options)
end

T["ACPHandler"]["Config Options"]["reflects config option changes in metadata"] = function()
  local result = child.lua([[
    local mock_connection = vim.deepcopy(_G.mock_acp_connection)
    mock_connection.session_id = "test-session-123"

    local config_opts = {
      {
        type = "select",
        id = "mode",
        name = "Mode",
        category = "mode",
        currentValue = "default",
        options = {
          { value = "default", name = "Always Ask" },
          { value = "plan", name = "Plan Mode" },
        },
      },
    }
    mock_connection._config_options = config_opts
    mock_connection.get_config_options = function(self)
      return self._config_options
    end

    local chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        handlers = { form_messages = function(a, m) return m end }
      }
    })

    chat.acp_connection = mock_connection
    chat:update_metadata()

    local metadata_before = vim.deepcopy(_G.codecompanion_chat_metadata[chat.bufnr])

    -- Simulate config option change
    config_opts[1].currentValue = "plan"

    chat:update_metadata()

    local metadata_after = _G.codecompanion_chat_metadata[chat.bufnr]

    return {
      mode_before = metadata_before.config_options and metadata_before.config_options.mode and metadata_before.config_options.mode.current,
      mode_after = metadata_after.config_options and metadata_after.config_options.mode and metadata_after.config_options.mode.current,
      name_after = metadata_after.config_options and metadata_after.config_options.mode and metadata_after.config_options.mode.name,
    }
  ]])

  h.eq("default", result.mode_before)
  h.eq("plan", result.mode_after)
  h.eq("Plan Mode", result.name_after)
end

return T
