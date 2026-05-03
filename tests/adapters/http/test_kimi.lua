local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Kimi adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("kimi")
    end,
  },
})

T["Kimi adapter"]["form_messages"] = new_set()

T["Kimi adapter"]["form_messages"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["Kimi adapter"]["form_messages"]["it can form messages with tools"] = function()
  local input = {
    { role = "system", content = "System Prompt 1" },
    { role = "user", content = "User1" },
    {
      role = "llm",
      tools = {
        calls = {
          {
            ["function"] = {
              arguments = '{"location":"London, UK","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_1_a460d461-60a7-468c-a699-ef9e2dced125",
            type = "function",
          },
          {
            ["function"] = {
              arguments = '{"location":"Paris, France","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_0_bb2a2194-a723-44a6-a1f8-bd05e9829eea",
            type = "function",
          },
        },
      },
    },
  }

  local expected = {
    messages = {
      {
        content = "System Prompt 1",
        role = "system",
      },
      {
        content = "User1",
        role = "user",
      },
      {
        role = "llm",
        tool_calls = {
          {
            ["function"] = {
              arguments = '{"location":"London, UK","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_1_a460d461-60a7-468c-a699-ef9e2dced125",
            type = "function",
          },
          {
            ["function"] = {
              arguments = '{"location":"Paris, France","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_0_bb2a2194-a723-44a6-a1f8-bd05e9829eea",
            type = "function",
          },
        },
      },
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, input))
end

T["Kimi adapter"]["form_messages"]["it can form tools to be sent to the API"] = function()
  adapter = require("codecompanion.adapters").extend("kimi", {
    schema = {
      model = {
        default = "kimi-k2.6",
      },
    },
  })

  local weather = require("tests.interactions.chat.tools.builtin.stubs.weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["Kimi adapter"]["form_messages"]["it rewrites m.reasoning to flat reasoning_content on assistant messages"] = function()
  -- Role is "assistant" here because CC's chat layer calls map_roles before
  -- form_messages, translating its internal LLM_ROLE constant.
  local input = {
    { role = "user", content = "What is Ruby?" },
    {
      role = "assistant",
      content = "Elegant simplicity.",
      reasoning = "Ruby is a dynamic, object-oriented language...",
    },
  }

  local result = adapter.handlers.form_messages(adapter, input)

  h.eq("Ruby is a dynamic, object-oriented language...", result.messages[2].reasoning_content)
  h.eq(nil, result.messages[2].reasoning)
  h.eq("Elegant simplicity.", result.messages[2].content)
end

T["Kimi adapter"]["form_messages"]["it inserts empty reasoning_content fallback for tool-call replays when think=true"] = function()
  -- Required for k2-thinking on tool-call history that pre-dates this adapter:
  -- the validator rejects assistant messages with tool_calls but no reasoning_content.
  adapter.parameters = adapter.parameters or {}
  adapter.parameters.think = true

  local input = {
    {
      role = "assistant",
      tools = {
        calls = {
          {
            id = "call_abc",
            type = "function",
            ["function"] = { name = "weather", arguments = '{"location":"London"}' },
          },
        },
      },
    },
  }

  local result = adapter.handlers.form_messages(adapter, input)
  h.eq("", result.messages[1].reasoning_content)
  h.eq("call_abc", result.messages[1].tool_calls[1].id)
end

T["Kimi adapter"]["form_messages"]["it does not insert reasoning_content fallback when think=false"] = function()
  adapter.parameters = adapter.parameters or {}
  adapter.parameters.think = false

  local input = {
    {
      role = "assistant",
      tools = {
        calls = {
          {
            id = "call_abc",
            type = "function",
            ["function"] = { name = "weather", arguments = "{}" },
          },
        },
      },
    },
  }

  local result = adapter.handlers.form_messages(adapter, input)
  h.eq(nil, result.messages[1].reasoning_content)
end

T["Kimi adapter"]["Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("kimi", {
        opts = {
          stream = true,
        },
      })
    end,
  },
})

T["Kimi adapter"]["Streaming"]["can output streamed data into a format for the chat buffer"] = function()
  local lines = vim.fn.readfile("tests/adapters/http/stubs/kimi_streaming.txt")
  local output = ""
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end
  h.eq("Elegant simplicity.", output)
end

T["Kimi adapter"]["Streaming"]["can process thinking"] = function()
  local content = ""
  local reasoning = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/kimi_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line, {})
    if chat_output and chat_output.extra and adapter.handlers.parse_message_meta then
      chat_output = adapter.handlers.parse_message_meta(adapter, chat_output)
    end
    if chat_output and chat_output.output then
      if chat_output.output.content then
        content = content .. chat_output.output.content
      end
      if chat_output.output.reasoning and chat_output.output.reasoning.content then
        reasoning = reasoning .. chat_output.output.reasoning.content
      end
    end
  end

  h.eq("Two words capturing Ruby.", reasoning)
  h.eq("Elegant simplicity.", content)
end

-- No streaming ---------------------------------------------------------------

T["Kimi adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("kimi", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Kimi adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/kimi_no_streaming.txt")
  data = table.concat(data, "\n")

  h.eq("Elegant simplicity.", adapter.handlers.chat_output(adapter, data).output.content)
end

T["Kimi adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/kimi_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location":"London, UK","units":"celsius"}',
        name = "weather",
      },
      id = "call_kimi_01",
      type = "function",
    },
    {
      _index = 2,
      ["function"] = {
        arguments = '{"location":"Paris, France","units":"celsius"}',
        name = "weather",
      },
      id = "call_kimi_02",
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

T["Kimi adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/kimi_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Elegant simplicity.", adapter.handlers.inline_output(adapter, json).output)
end

return T
