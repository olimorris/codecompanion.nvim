local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["OpenAI adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("openai")
    end,
  },
})

T["OpenAI adapter"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["OpenAI adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests/strategies/chat/agents/tools/stubs/weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["OpenAI adapter"]["Streaming"] = new_set()

T["OpenAI adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/stubs/openai_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Dynamic, Flexible", output)
end

T["OpenAI adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/stubs/openai_tools_streaming.txt")
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
      id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
      type = "function",
    },
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "Paris", "units": "celsius"}',
        name = "weather",
      },
      id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
      type = "function",
    },
  }

  h.eq(tool_output, tools)

  local formatted_tools = {
    {
      arguments = {
        location = "London",
        units = "celsius",
      },
      name = "weather",
    },
    {
      arguments = {
        location = "Paris",
        units = "celsius",
      },
      name = "weather",
    },
  }

  h.eq(formatted_tools, adapter.handlers.tools_output(adapter, tools))
end

T["OpenAI adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("openai", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["OpenAI adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/openai_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Elegant simplicity.", adapter.handlers.chat_output(adapter, json).output.content)
end

T["OpenAI adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/openai_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "London, United Kingdom", "units": "celsius"}',
        name = "weather",
      },
      id = "call_VGkXa0hqNLEe2HSgMO1EpOe6",
      type = "function",
    },
    {
      _index = 2,
      ["function"] = {
        arguments = '{"location": "Paris, France", "units": "celsius"}',
        name = "weather",
      },
      id = "call_HVrmLOHM2Ybd6K7vQj4x8NdQ",
      type = "function",
    },
  }
  h.eq(tool_output, tools)

  local formatted_tools = {
    {
      arguments = {
        location = "London, United Kingdom",
        units = "celsius",
      },
      name = "weather",
    },
    {
      arguments = {
        location = "Paris, France",
        units = "celsius",
      },
      name = "weather",
    },
  }

  h.eq(formatted_tools, adapter.handlers.tools_output(adapter, tools))
end

T["OpenAI adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/openai_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Elegant simplicity.", adapter.handlers.inline_output(adapter, json).output)
end

return T
