local helpers = require("tests.helpers")
local h = helpers

local Chat = require("codecompanion.strategies.chat")
local config = require("codecompanion.config")

local T = {}

-- Setup test environment
local function setup_test_config()
  -- Enable iteration features
  config.strategies.chat.iteration = {
    enabled = true,
    max_iterations_per_task = 3,
    iteration_increase_amount = 2,
    show_iteration_progress = false, -- Disable for testing
    context_summarization = {
      enabled = true,
      threshold_ratio = 0.1, -- Very low threshold for testing
      keep_recent_messages = 2,
      max_summary_tokens = 100,
      preserve_tools = true,
    },
    context_limits = {
      default = 50, -- Very small for testing
      test_adapter = 50,
    },
  }
end

-- Mock adapter for testing
local function create_mock_adapter()
  return {
    name = "test_adapter",
    formatted_name = "Test Adapter",
    schema = {
      model = { default = "test-model" },
      context_window = { default = 50 },
    },
    handlers = {
      chat_output = function(adapter, data, tools)
        return {
          status = "success",
          output = {
            content = "Test response from LLM",
            role = config.constants.LLM_ROLE,
          },
        }
      end,
      tools = {
        format_tool_calls = function(adapter, tools)
          return tools
        end,
      },
    },
    map_roles = function(self, messages)
      return messages
    end,
    map_schema_to_params = function(self, settings)
      return settings or {}
    end,
  }
end

-- Mock HTTP client
local function setup_mock_http()
  package.loaded["codecompanion.http"] = {
    new = function()
      return {
        request = function(payload, callbacks)
          vim.schedule(function()
            callbacks.callback(nil, { test = "data" }, create_mock_adapter())
            callbacks.done()
          end)
          return { test = "request" }
        end,
      }
    end,
  }
end

-- Mock vim functions for testing
local function setup_vim_mocks()
  local original_confirm = vim.fn.confirm
  local confirm_responses = {}
  local confirm_call_count = 0

  vim.fn.confirm = function(message, choices, default, type)
    confirm_call_count = confirm_call_count + 1
    return confirm_responses[confirm_call_count] or 1
  end

  return {
    set_confirm_response = function(responses)
      confirm_responses = responses
      confirm_call_count = 0
    end,
    restore = function()
      vim.fn.confirm = original_confirm
    end,
  }
end

T["LLM Iteration Integration"] = {}

T["LLM Iteration Integration"]["initializes iteration components when enabled"] = function()
  setup_test_config()
  setup_mock_http()

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  h.eq("table", type(chat.context_summarizer))
  h.eq("table", type(chat.iteration_manager))
  h.eq(3, chat.iteration_manager.max_iterations)
end

T["LLM Iteration Integration"]["skips iteration components when disabled"] = function()
  -- Temporarily disable iteration
  local original_enabled = config.strategies.chat.iteration.enabled
  config.strategies.chat.iteration.enabled = false

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  h.eq(nil, chat.context_summarizer)
  h.eq(nil, chat.iteration_manager)

  -- Restore original setting
  config.strategies.chat.iteration.enabled = original_enabled
end

T["LLM Iteration Integration"]["tracks iterations during submit"] = function()
  setup_test_config()
  setup_mock_http()

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  -- Add a test message
  chat:add_message({
    role = config.constants.USER_ROLE,
    content = "Test message",
  })

  -- Submit should increment iteration count
  local initial_iterations = chat.iteration_manager.current_iterations
  chat:submit({ skip_summarization = true }) -- Skip summarization for this test

  -- Wait for async completion
  vim.wait(100)

  h.eq(initial_iterations + 1, chat.iteration_manager.current_iterations)
end

T["LLM Iteration Integration"]["blocks submit when iteration limit reached"] = function()
  setup_test_config()
  setup_mock_http()
  local vim_mocks = setup_vim_mocks()
  vim_mocks.set_confirm_response({ 2 }) -- User cancels

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  -- Manually set iterations to limit
  chat.iteration_manager.current_iterations = 2 -- Will be 3 after increment

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = "Test message",
  })

  -- This should be blocked
  chat:submit({ skip_summarization = true })

  -- Should not proceed with the request
  h.eq(3, chat.iteration_manager.current_iterations)

  vim_mocks.restore()
end

T["LLM Iteration Integration"]["allows continuation when user approves"] = function()
  setup_test_config()
  setup_mock_http()
  local vim_mocks = setup_vim_mocks()
  vim_mocks.set_confirm_response({ 1 }) -- User continues

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  -- Manually set iterations to limit
  chat.iteration_manager.current_iterations = 2

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = "Test message",
  })

  -- This should prompt user and then continue
  chat:submit({ skip_summarization = true })

  -- Should have increased the limit
  h.eq(5, chat.iteration_manager.max_iterations) -- 3 + 2 = 5

  vim_mocks.restore()
end

T["LLM Iteration Integration"]["performs context summarization when needed"] = function()
  setup_test_config()
  setup_mock_http()

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  -- Add many messages to trigger summarization
  for i = 1, 10 do
    chat:add_message({
      role = config.constants.USER_ROLE,
      content = "This is a longer test message number " .. i .. " that should trigger summarization",
    })
  end

  local original_message_count = #chat.messages

  -- Check that summarization would be triggered
  local should_summarize = chat.context_summarizer:should_summarize(
    chat.messages,
    50, -- context limit
    0.1 -- very low threshold
  )

  h.eq(true, should_summarize)

  -- Test the summarization process
  local summarized_messages = chat:check_and_summarize_context(chat.messages, {})

  -- Should have fewer messages after summarization
  h.lt(#summarized_messages, original_message_count)

  -- Should have a summary message
  local has_summary = false
  for _, msg in ipairs(summarized_messages) do
    if msg.opts and msg.opts.tag == "context_summary" then
      has_summary = true
      break
    end
  end
  h.eq(true, has_summary)
end

T["LLM Iteration Integration"]["resets iterations when chat is cleared"] = function()
  setup_test_config()
  setup_mock_http()

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  -- Simulate some iterations
  chat.iteration_manager:increment_and_check("test")
  chat.iteration_manager:increment_and_check("test")

  h.eq(2, chat.iteration_manager.current_iterations)

  -- Clear should reset iterations
  chat:clear()

  h.eq(0, chat.iteration_manager.current_iterations)
  h.eq(0, #chat.iteration_manager.iteration_history)
end

T["LLM Iteration Integration"]["gets context limit correctly"] = function()
  setup_test_config()

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  local context_limit = chat:get_context_limit({})

  -- Should use the test_adapter specific limit
  h.eq(50, context_limit)
end

T["LLM Iteration Integration"]["falls back to default context limit"] = function()
  setup_test_config()

  local adapter = create_mock_adapter()
  adapter.name = "unknown_adapter"

  local chat = Chat.new({
    adapter = adapter,
    context = {},
  })

  local context_limit = chat:get_context_limit({})

  -- Should fall back to default
  h.eq(50, context_limit) -- Using test default
end

T["LLM Iteration Integration"]["handles summarization errors gracefully"] = function()
  setup_test_config()

  -- Mock HTTP client that fails
  package.loaded["codecompanion.http"] = {
    new = function()
      return {
        request = function(payload, callbacks)
          vim.schedule(function()
            callbacks.callback({ stderr = "Test error" }, nil, nil)
            callbacks.done()
          end)
          return { test = "request" }
        end,
      }
    end,
  }

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  -- Add messages to trigger summarization
  for i = 1, 5 do
    chat:add_message({
      role = config.constants.USER_ROLE,
      content = "Test message " .. i,
    })
  end

  local original_messages = vim.deepcopy(chat.messages)
  local result_messages = chat:check_and_summarize_context(chat.messages, {})

  -- Should return original messages on error
  h.eq(#original_messages, #result_messages)
end

T["LLM Iteration Integration"]["tracks tool execution iterations"] = function()
  setup_test_config()
  setup_mock_http()

  local chat = Chat.new({
    adapter = create_mock_adapter(),
    context = {},
  })

  local initial_iterations = chat.iteration_manager.current_iterations

  -- Simulate tool execution
  chat:done({}, {
    {
      name = "test_tool",
      arguments = "{}",
    },
  })

  -- Should have incremented iteration count
  h.eq(initial_iterations + 1, chat.iteration_manager.current_iterations)
end

return T
