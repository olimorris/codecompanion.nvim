local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["OpenAI Responses adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("openai_responses")
    end,
  },
})

T["OpenAI Responses adapter"]["form_messages"] = new_set()

T["OpenAI Responses adapter"]["form_messages"]["messages only"] = function()
  local messages = {
    {
      content = "You are a helpful assistant.",
      role = "system",
    },
    {
      content = "Who knows about Ruby",
      role = "system",
    },
    {
      content = "Explain Ruby in two words",
      role = "user",
    },
  }

  h.eq({
    instructions = messages[1].content .. "\n" .. messages[2].content,
    input = {
      {
        role = messages[3].role,
        content = messages[3].content,
      },
    },
  }, adapter.handlers.form_messages(adapter, messages))
end

T["OpenAI Responses adapter"]["form_messages"]["images"] = function()
  local messages = {
    {
      _meta = { sent = true },
      content = "How are you?",
      role = "user",
    },
    {
      _meta = { sent = true },
      content = "I am fine, thanks. How can I help?",
      role = "assistant",
    },
    {
      content = "somefakebase64encoding",
      role = "user",
      opts = {
        mimetype = "image/jpg",
        context_id = "<image>https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg</image>",
        tag = "image",
        visible = false,
      },
    },
    {
      content = "What is this an image of?",
      role = "user",
    },
  }

  local expected = {
    input = {
      {
        content = "How are you?",
        role = "user",
      },
      {
        content = "I am fine, thanks. How can I help?",
        role = "assistant",
      },
      {
        content = {
          {
            type = "input_image",
            image_url = "data:image/jpg;base64,somefakebase64encoding",
          },
          {
            type = "input_text",
            text = "What is this an image of?",
          },
        },
        role = "user",
      },
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, messages))
end

T["OpenAI Responses adapter"]["form_messages"]["format available tools to call"] = function()
  local weather = require("tests.strategies.chat.tools.catalog.stubs.weather").schema
  local tools = { weather = { weather } }

  local expected = {
    ["type"] = "function",
    ["name"] = "weather",
    ["description"] = "Retrieves current weather for the given location.",
    ["parameters"] = {
      ["type"] = "object",
      ["properties"] = {
        ["location"] = {
          ["type"] = "string",
          ["description"] = "City and country e.g. Bogotá, Colombia",
        },
        ["units"] = {
          ["type"] = "string",
          ["enum"] = { "celsius", "fahrenheit" },
          ["description"] = "Units the temperature will be returned in.",
        },
      },
      ["required"] = { "location", "units" },
      ["additionalProperties"] = false,
    },
    ["strict"] = true,
  }

  -- We need to adjust the tools format slightly with Responses
  -- https://platform.openai.com/docs/api-reference/responses
  h.eq({ tools = { expected } }, adapter.handlers.form_tools(adapter, tools))
end

T["OpenAI Responses adapter"]["form_messages"]["format tool calls"] = function()
  local messages = {
    {
      role = "assistant",
      tool_calls = {
        {
          _index = 0,
          id = "fc_0cf9af0f913994140068e2713964448193a723d7191832a56f",
          call_id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
          ["function"] = {
            name = "weather",
            arguments = '{"location": "London", "units": "celsius"}',
          },
        },
        {
          _index = 1,
          id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
          call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
          ["function"] = {
            name = "weather",
            arguments = '{"location": "Paris", "units": "celsius"}',
          },
        },
      },
    },
  }

  local expected = {
    {
      type = "function_call",
      id = "fc_0cf9af0f913994140068e2713964448193a723d7191832a56f",
      call_id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
      name = "weather",
      arguments = '{"location": "London", "units": "celsius"}',
    },
    {
      type = "function_call",
      id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
      call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
      name = "weather",
      arguments = '{"location": "Paris", "units": "celsius"}',
    },
  }

  h.eq({ input = expected }, adapter.handlers.form_messages(adapter, messages))
end

T["OpenAI Responses adapter"]["form_messages"]["format tool output"] = function()
  local messages = {
    {
      role = "tool",
      content = "The weather in London is 15 degrees",
      tool_call_id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
      tool_id = "fc_0cf9af0f913994140068e2713964448193a723d7191832a56f",
    },
    {
      role = "tool",
      content = "The weather in Paris is 15 degrees",
      tool_call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
      tool_id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
    },
  }

  local expected = {
    {
      type = "function_call_output",
      call_id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
      output = "The weather in London is 15 degrees",
    },
    {
      type = "function_call_output",
      call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
      output = "The weather in Paris is 15 degrees",
    },
  }

  h.eq({ input = expected }, adapter.handlers.form_messages(adapter, messages))
end

T["OpenAI Responses adapter"]["chat_output"] = new_set()

T["OpenAI Responses adapter"]["chat_output"]["can output tool calls"] = function()
  local output = "The weather in London is 15 degrees"
  local tool_call = {
    ["function"] = {
      arguments = '{"location": "London", "units": "celsius"}',
      name = "weather",
    },
    id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
    call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
    type = "function",
  }

  h.eq({
    content = output,
    opts = {
      visible = false,
    },
    role = "tool",
    tool_id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
    tool_call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
  }, adapter.handlers.tools.output_response(adapter, tool_call, output))
end

T["OpenAI Responses adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("openai_responses", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["OpenAI Responses adapter"]["No Streaming"]["chat_output"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic, expressive", adapter.handlers.chat_output(adapter, json).output.content)
end

T["OpenAI Responses adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_tools_no_streaming.txt")
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
      call_id = "call_tgWgQU4IzqjLCPTdsbODFoOh",
      id = "fc_07f118f077c91f1a0068e4319f231481969324b4a9180f3bda",
      type = "function",
    },
    {
      _index = 2,
      ["function"] = {
        arguments = '{"location":"Paris, France","units":"celsius"}',
        name = "weather",
      },
      call_id = "call_kGgpknBihLExIymnhL9421wC",
      id = "fc_07f118f077c91f1a0068e4319f6ac481969fde8ab4fb4e0f50",
      type = "function",
    },
  }
  h.eq(tool_output, tools)
end

T["OpenAI Responses adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic, expressive", adapter.handlers.inline_output(adapter, json).output)
end

T["OpenAI Responses adapter"]["No Streaming"]["can process reasoning output"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_reasoning_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    "First block\n\nSecond block\n\nThird block\n\nFourth block",
    adapter.handlers.chat_output(adapter, json).output.reasoning.content
  )
end

T["OpenAI Responses adapter"]["Streaming"] = new_set()

T["OpenAI Responses adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Elegant language", output)
end

T["OpenAI Responses adapter"]["Streaming"]["can process reasoning output"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_reasoning_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output and chat_output.output.reasoning and chat_output.output.reasoning.content then
      output = output .. chat_output.output.reasoning.content
    end
  end

  h.expect_starts_with("**summarizing ruby's strengths**", output)
end

T["OpenAI Responses adapter"]["Streaming"]["can process tools"] = function()
  -- Adds tool calls to the tools table
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local expected = {
    {
      _index = 0,
      ["function"] = {
        arguments = '{"location":"London, UK","units":"celsius"}',
        name = "weather",
      },
      id = "fc_0cf9af0f913994140068e2713964448193a723d7191832a56f",
      call_id = "call_L07YMw4V0erO5h5JvtKV3AMh",
      type = "function",
    },
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location":"Paris, France","units":"celsius"}',
        name = "weather",
      },
      id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
      call_id = "call_tY62Os9Hez2R2twVYRnYyGYq",
      type = "function",
    },
  }

  h.eq(expected, tools)
end

return T
