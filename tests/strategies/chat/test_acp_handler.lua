local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')

        -- Mock ACP connection for chat integration tests
        _G.mock_acp_connection = {
          connected = false,
          session_id = nil,

          connect = function(self)
            self.connected = true
            self.session_id = "test-session-123"
            return self
          end,

          prompt = function(self, messages)
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
          end
        }
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.mock_acp_connection = nil
        _G.last_prompt_request = nil
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

    local ACPHandler = require("codecompanion.strategies.chat.acp_handler")
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

  h.eq(true, result.has_connection)
  h.eq(true, result.connection_established)
  h.eq("test-session-123", result.session_id)
  h.eq(true, result.request_sent)
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

    local ACPHandler = require("codecompanion.strategies.chat.acp_handler")
    local handler = ACPHandler.new(chat)

    -- Track what gets added to the buffer
    local buffer_messages = {}
    chat.add_buf_message = function(self, data, opts)
      table.insert(buffer_messages, { data = data, opts = opts })
    end

    -- Simulate message chunk handling
    handler:_handle_message_chunk("Hello ")
    handler:_handle_message_chunk("there!")

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

    local ACPHandler = require("codecompanion.strategies.chat.acp_handler")
    local handler = ACPHandler.new(chat)

    local buffer_messages = {}
    chat.add_buf_message = function(self, data, opts)
      table.insert(buffer_messages, { data = data, opts = opts })
    end

    -- Simulate thought chunk handling
    handler:_handle_thought_chunk("Let me think about this...")
    handler:_handle_thought_chunk("I need to consider...")

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

    local ACPHandler = require("codecompanion.strategies.chat.acp_handler")
    local handler = ACPHandler.new(chat)

    -- Track completion calls
    local completion_data = {}
    chat.done = function(self, output, reasoning, tools)
      completion_data = { output = output, reasoning = reasoning, tools = tools }
    end

    -- Simulate full interaction
    handler:_handle_message_chunk("Response part 1")
    handler:_handle_message_chunk(" and part 2")
    handler:_handle_thought_chunk("My reasoning")
    handler:_handle_completion("end_turn")

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

    local ACPHandler = require("codecompanion.strategies.chat.acp_handler")
    local handler = ACPHandler.new(chat)

    -- Mock connection failure
    package.loaded["codecompanion.acp"] = {
      new = function(args)
        return {
          connect = function() return nil end -- Connection fails
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
  h.eq(true, result.completion_called)
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
  h.eq(true, result.payload_submitted)
  h.eq(true, result.has_messages)
  h.eq(true, result.last_prompt_set)
end

return T
