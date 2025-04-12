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

T["DeepSeek adapter"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["DeepSeek adapter"]["merges consecutive messages with the same role"] = function()
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

T["DeepSeek adapter"]["merges system messages together at the start of the message chain"] = function()
  local input = {
    { role = "system", content = "System Prompt 1" },
    { role = "user", content = "User1" },
    { role = "system", content = "System Prompt 2" },
    { role = "system", content = "System Prompt 3" },
    { role = "assistant", content = "Assistant1" },
  }

  local expected = {
    messages = {
      { role = "system", content = "System Prompt 1\n\nSystem Prompt 2\n\nSystem Prompt 3" },
      { role = "user", content = "User1" },
      { role = "assistant", content = "Assistant1" },
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, input))
end

T["DeepSeek adapter"]["it can form tools to be sent to the API"] = function()
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
  local lines = vim.fn.readfile("tests/adapters/stubs/deepseek_streaming.txt")
  local output = ""
  for _, line in ipairs(lines) do
    output = output .. (adapter.handlers.chat_output(adapter, line).output.reasoning or "")
  end
  h.expect_starts_with("Okay, the user wants me to explain Ruby in two words. ", output)
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
      type = "function",
    },
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "Paris", "units": "celsius"}',
        name = "weather",
      },
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

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
      type = "function",
    },
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "Paris", "units": "celsius"}',
        name = "weather",
      },
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
