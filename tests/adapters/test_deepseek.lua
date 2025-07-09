local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["DeepSeek adapter"] = new_set({
  hooks = {
    pre_case = function()
      require("codecompanion")
      adapter = require("codecompanion.adapters").resolve("deepseek")
    end,
  },
})

T["DeepSeek adapter"]["form_messages"] = new_set()

T["DeepSeek adapter"]["form_messages"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["DeepSeek adapter"]["form_messages"]["merges consecutive messages with the same role"] = function()
  local input = {
    { role = "user", content = "A" },
    { role = "user", content = "B" },
    { role = "assistant", content = "C" },
    { role = "assistant", content = "D" },
    { role = "user", content = "E" },
  }

  local expected = {
    messages = {
      { role = "user", content = "A\n\nB" },
      { role = "assistant", content = "C\n\nD" },
      { role = "user", content = "E" },
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, input))
end

T["DeepSeek adapter"]["form_messages"]["merges system messages together at the start of the message chain"] = function()
  local input = {
    { role = "system", content = "System Prompt 1" },
    { role = "user", content = "User1" },
    { role = "system", content = "System Prompt 2" },
    { role = "system", content = "System Prompt 3" },
  }

  local expected = {
    messages = {
      {
        content = "System Prompt 1 System Prompt 2\n\nSystem Prompt 3",
        role = "system",
      },
      {
        content = "User1",
        role = "user",
      },
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, input))
end

T["DeepSeek adapter"]["form_messages"]["ensures message content is a string and not a list"] = function()
  -- Ref: https://github.com/BerriAI/litellm/issues/6642
  local input = {
    { role = "user", content = "Describe Ruby in two words" },
    { role = "assistant", content = { "Elegant, Simple." } },
  }

  local expected = {
    messages = {
      {
        content = "Describe Ruby in two words",
        role = "user",
      },
      {
        content = "Elegant, Simple.",
        role = "assistant",
      },
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, input))
end

T["DeepSeek adapter"]["form_messages"]["it can form messages with tools"] = function()
  local input = {
    { role = "system", content = "System Prompt 1" },
    { role = "user", content = "User1" },
    { role = "system", content = "System Prompt 2" },
    { role = "system", content = "System Prompt 3" },
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
  }

  local expected = {
    messages = {
      {
        content = "System Prompt 1 System Prompt 2\n\nSystem Prompt 3",
        role = "system",
      },
      {
        content = "User1",
        role = "user",
      },
      {
        content = "",
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

T["DeepSeek adapter"]["form_messages"]["it can form tools to be sent to the API"] = function()
  adapter = require("codecompanion.adapters").extend("deepseek", {
    schema = {
      model = {
        default = "deepseek-chat",
      },
    },
  })

  local weather = require("tests/strategies/chat/agents/tools/stubs/weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["DeepSeek adapter"]["Streaming"] = new_set()

T["DeepSeek adapter"]["Streaming"]["can output streamed data into a format for the chat buffer"] = function()
  local lines = vim.fn.readfile("tests/adapters/stubs/deepseek_streaming.txt")
  local output = ""
  for _, line in ipairs(lines) do
    output = output .. (adapter.handlers.chat_output(adapter, line).output.content or "")
  end
  h.eq(
    "Dynamic. Expressive.\n\nNext, you might ask about Ruby's key features or how it compares to other languages.",
    output
  )
end

T["DeepSeek adapter"]["Streaming"]["can handle reasoning content when streaming"] = function()
  local output = {
    content = "",
    reasoning = {
      content = "",
    },
  }

  local lines = vim.fn.readfile("tests/adapters/stubs/deepseek_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output then
      if chat_output.output.reasoning and chat_output.output.reasoning.content then
        output.reasoning.content = output.reasoning.content .. chat_output.output.reasoning.content
      end
      if chat_output.output.content then
        output.content = output.content .. chat_output.output.content
      end
    end
  end

  h.expect_starts_with("Okay, the user wants me to explain Ruby in two words. ", output.reasoning.content)
end

T["DeepSeek adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/stubs/deepseek_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 0,
      ["function"] = {
        arguments = '{"location": "London", "units": "celsius"}',
        name = "weather",
      },
      id = "call_0_bb2a2194-a723-44a6-a1f8-bd05e9829eea",
      type = "function",
    },
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "Paris", "units": "celsius"}',
        name = "weather",
      },
      id = "call_1_a460d461-60a7-468c-a699-ef9e2dced125",
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

-- No streaming ---------------------------------------------------------------

T["DeepSeek adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("deepseek", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["DeepSeek adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/deepseek_no_streaming.txt")
  data = table.concat(data, "\n")

  h.eq("Elegant simplicity.", adapter.handlers.chat_output(adapter, data).output.content)
end

T["DeepSeek adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/deepseek_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 0,
      ["function"] = {
        arguments = '{"location": "London", "units": "celsius"}',
        name = "weather",
      },
      id = "call_0_74655864-c1ab-455f-88c5-921aa7b6281c",
      type = "function",
    },
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "Paris", "units": "celsius"}',
        name = "weather",
      },
      id = "call_1_759f62c3-f8dc-475f-9558-8211fc0a133c",
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

T["DeepSeek adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/deepseek_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Elegant simplicity.", adapter.handlers.inline_output(adapter, json).output)
end

return T
