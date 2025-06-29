local helpers = require("tests.helpers")
local h = helpers

local ContextSummarizer = require("codecompanion.strategies.chat.context_summarizer")
local config = require("codecompanion.config")

local T = {}

-- Mock adapter for testing
local mock_adapter = {
  name = "test_adapter",
  schema = {
    model = { default = "test-model" },
    context_window = { default = 4096 },
  },
  handlers = {
    chat_output = function(adapter, data, tools)
      return {
        status = "success",
        output = {
          content = "This is a test summary of the conversation.",
        },
      }
    end,
  },
  map_roles = function(messages)
    return messages
  end,
  map_schema_to_params = function(settings)
    return settings
  end,
}

-- Mock chat instance
local mock_chat = {
  id = 12345,
  bufnr = 1,
  adapter = mock_adapter,
}

-- Mock HTTP client for testing
local mock_http_client = {
  request = function(payload, callbacks)
    -- Simulate successful summarization
    vim.schedule(function()
      callbacks.callback(nil, { test = "data" }, mock_adapter)
      callbacks.done()
    end)
    return { test = "request" }
  end,
}

-- Override the HTTP client for testing
package.loaded["codecompanion.http"] = {
  new = function()
    return mock_http_client
  end,
}

T["ContextSummarizer"] = {}

T["ContextSummarizer"]["can be created"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  h.eq("table", type(summarizer))
  h.eq(mock_chat, summarizer.chat)
  h.eq(mock_adapter, summarizer.adapter)
end

T["ContextSummarizer"]["calculates tokens correctly"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  local messages = {
    { content = "Hello" }, -- ~1.25 tokens
    { content = "How are you today?" }, -- ~4 tokens
  }

  local token_count = summarizer:calculate_tokens(messages)
  h.eq(6, token_count) -- ceil(5/4) + ceil(16/4) = 2 + 4 = 6
end

T["ContextSummarizer"]["determines when summarization is needed"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  local short_messages = {
    { content = "Hello" },
  }

  local long_messages = {}
  for i = 1, 100 do
    table.insert(long_messages, { content = "This is a longer message that takes up more tokens." })
  end

  h.eq(false, summarizer:should_summarize(short_messages, 1000, 0.75))
  h.eq(true, summarizer:should_summarize(long_messages, 100, 0.75))
end

T["ContextSummarizer"]["splits messages correctly"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  local messages = {}
  for i = 1, 10 do
    table.insert(messages, { content = "Message " .. i })
  end

  local to_summarize, to_keep = summarizer:split_messages_for_summary(messages, 3)

  h.eq(7, #to_summarize) -- 10 - 3 = 7
  h.eq(3, #to_keep)
  h.eq("Message 8", to_keep[1].content)
  h.eq("Message 10", to_keep[3].content)
end

T["ContextSummarizer"]["formats messages for summary"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  local messages = {
    {
      role = config.constants.USER_ROLE,
      content = "Hello",
    },
    {
      role = config.constants.LLM_ROLE,
      content = "Hi there!",
      tool_calls = {
        { name = "test_tool", arguments = '{"param": "value"}' },
      },
    },
  }

  local formatted = summarizer:format_messages_for_summary(messages)

  h.match("=== CONVERSATION HISTORY TO SUMMARIZE ===", formatted)
  h.match("--- USER MESSAGE 1 ---", formatted)
  h.match("Hello", formatted)
  h.match("--- ASSISTANT MESSAGE 2 ---", formatted)
  h.match("Hi there!", formatted)
  h.match("test_tool", formatted)
  h.match("=== END CONVERSATION HISTORY ===", formatted)
end

T["ContextSummarizer"]["builds summarization prompt"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  local basic_prompt = summarizer:build_summarization_prompt({})
  h.match("expert conversation summarizer", basic_prompt)
  h.match("concise but comprehensive", basic_prompt)

  local context_prompt = summarizer:build_summarization_prompt({
    current_task = "Testing the system",
    preserve_tools = true,
  })
  h.match("Testing the system", context_prompt)
  h.match("tool usage", context_prompt)
end

T["ContextSummarizer"]["generates summary successfully"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = { max_summary_tokens = 500 },
  })

  local messages = {
    {
      role = config.constants.USER_ROLE,
      content = "Can you help me with a task?",
    },
    {
      role = config.constants.LLM_ROLE,
      content = "Of course! What do you need help with?",
    },
  }

  local summary, error_msg = summarizer:summarize(messages, {
    current_task = "Getting help",
    preserve_tools = false,
  })

  h.eq(nil, error_msg)
  h.eq("string", type(summary))
  h.match("test summary", summary)
end

T["ContextSummarizer"]["handles empty messages"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  local summary, error_msg = summarizer:summarize({}, {})

  h.eq(nil, summary)
  h.eq("No messages to summarize", error_msg)
end

T["ContextSummarizer"]["handles few messages correctly"] = function()
  local summarizer = ContextSummarizer.new({
    chat = mock_chat,
    adapter = mock_adapter,
    config = {},
  })

  local messages = {
    { content = "Message 1" },
    { content = "Message 2" },
  }

  local to_summarize, to_keep = summarizer:split_messages_for_summary(messages, 3)

  h.eq(0, #to_summarize)
  h.eq(2, #to_keep)
end

return T 