local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Responses"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("openai_responses")
    end,
  },
})

T["Responses"]["can form reasoning output"] = function()
  local input = {
    {
      content = "Ruby ",
    },
    {
      content = "is a ",
    },
    {
      content = "dynamic, expressive programming language",
    },
    {
      id = "rs_123",
      encrypted_content = "somefakebase64encoding",
    },
  }

  local expected = {
    content = "Ruby is a dynamic, expressive programming language",
    id = "rs_123",
    encrypted_content = "somefakebase64encoding",
  }

  h.eq(expected, adapter.handlers.request.build_reasoning(adapter, input))
end

T["Responses"]["can output tool calls"] = function()
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
    tools = {
      id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
      call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
    },
  }, adapter.handlers.tools.format_response(adapter, tool_call, output))
end

T["Responses"]["build_messages"] = new_set()

T["Responses"]["build_messages"]["messages only"] = function()
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
  }, adapter.handlers.request.build_messages(adapter, messages))
end

T["Responses"]["build_messages"]["images"] = function()
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
        visible = false,
      },
      context = {
        id = "<image>https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg</image>",
        mimetype = "image/jpg",
      },
      _meta = {
        tag = "image",
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

  h.eq(expected, adapter.handlers.request.build_messages(adapter, messages))
end

T["Responses"]["build_messages"]["format available tools to call"] = function()
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
          ["type"] = { "string", "null" },
          ["description"] = "City and country e.g. Bogotá, Colombia",
        },
        ["units"] = {
          ["type"] = { "string", "null" },
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
  h.eq({ tools = { expected } }, adapter.handlers.request.build_tools(adapter, tools, { strict_mode = false }))
end

T["Responses"]["build_messages"]["format tool calls"] = function()
  local messages = {
    {
      role = "assistant",
      tools = {
        calls = {
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

  h.eq({ input = expected }, adapter.handlers.request.build_messages(adapter, messages))
end

T["Responses"]["build_messages"]["format tool output"] = function()
  local messages = {
    {
      role = "tool",
      content = "The weather in London is 15 degrees",
      tools = {
        call_id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
        id = "fc_0cf9af0f913994140068e2713964448193a723d7191832a56f",
      },
    },
    {
      role = "tool",
      content = "The weather in Paris is 15 degrees",
      tools = {
        call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
        id = "fc_0cf9af0f913994140068e27139a1948193bbf214a9664ec92c",
      },
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

  h.eq({ input = expected }, adapter.handlers.request.build_messages(adapter, messages))
end

T["Responses"]["build_messages"]["can handle reasoning"] = function()
  local messages = {
    {
      _meta = {
        sent = true,
        cycle = 1,
      },
      content = "Can you tell me what the the weather tool is for London and Paris?",
      id = 449094129,
      opts = {
        visible = true,
      },
      role = "user",
    },
    {
      _meta = { cycle = 1 },
      id = 486936684,
      opts = {
        visible = false,
      },
      reasoning = {
        encrypted_content = "somefakebase64encoding",
        reasoning_id = "rs_123",
        content = "I need to workout the weather",
      },
      role = "llm",
      tools = {
        calls = {
          {
            call_id = "call_balVirseGsQYwrVoigfUfF5G",
            ["function"] = {
              arguments = '{"location":"London, United Kingdom","units":"celsius"}',
              name = "weather",
            },
            id = "fc_08b1c96172854ff00168e8340c67c8819387d953e1ce970203",
            type = "function",
          },
          {
            call_id = "call_zktz1zuc65awPKojbwCKMLOD",
            ["function"] = {
              arguments = '{"location":"Paris, France","units":"celsius"}',
              name = "weather",
            },
            id = "fc_08b1c96172854ff00168e8340c7dec8193a11f0eedd9a85af5",
            type = "function",
          },
        },
      },
    },
    {
      content = "Ran the weather tool The weather in London, United Kingdom is 15° celsius",
      _meta = { cycle = 1 },
      id = 1997051449,
      opts = {
        visible = true,
      },
      role = "tool",
      tools = {
        call_id = "call_balVirseGsQYwrVoigfUfF5G",
        id = "fc_08b1c96172854ff00168e8340c67c8819387d953e1ce970203",
      },
    },
    {
      content = "Ran the weather tool The weather in Paris, France is 15° celsius",
      _meta = {
        cycle = 1,
      },
      id = 210818266,
      opts = {
        visible = true,
      },
      role = "tool",
      tools = {
        call_id = "call_zktz1zuc65awPKojbwCKMLOD",
        id = "fc_08b1c96172854ff00168e8340c7dec8193a11f0eedd9a85af5",
      },
    },
    {
      _meta = {
        response_id = "resp_123",
        cycle = 1,
      },
      content = "- London: 15°C\n- Paris: 15°C\n\nNeed anything else, like Fahrenheit or a weekly forecast?",
      id = 933614700,
      opts = {
        visible = true,
      },
      role = "llm",
    },
  }

  local result = adapter.handlers.request.build_messages(adapter, messages)

  h.eq({
    summary = { {
      text = "I need to workout the weather",
      type = "summary_text",
    } },
    encrypted_content = "somefakebase64encoding",
    type = "reasoning",
  }, result.input[2])
end

T["Responses"]["build_tools"] = new_set()

T["Responses"]["build_tools"]["format available tools to call"] = function()
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
  h.eq({ tools = { expected } }, adapter.handlers.request.build_tools(adapter, tools))
end

T["Responses"]["build_tools"]["can format for an adapter's remote tools"] = function()
  local tools = {
    {
      ["<tool>web_search</tool>"] = {
        _meta = {
          adapter_tool = true,
        },
        description = "Allow models to search the web for the latest information before generating a response.",
        name = "web_search",
      },
    },
  }

  h.eq({ tools = { { type = "web_search" } } }, adapter.handlers.request.build_tools(adapter, tools))
end

T["Responses"]["No Streaming"] = new_set({
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

T["Responses"]["No Streaming"]["chat_output"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic, expressive", adapter.handlers.response.parse_chat(adapter, json).output.content)
end

T["Responses"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.response.parse_chat(adapter, json, tools)

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

T["Responses"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_inline.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    '{"code": "print(\'Hello World\')","language": "lua","placement": "add"}',
    adapter.handlers.response.parse_inline(adapter, json).output
  )
end

T["Responses"]["No Streaming"]["can process reasoning output"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_reasoning_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_contains(
    "**Choosing descriptive terms**",
    adapter.handlers.response.parse_chat(adapter, json).output.reasoning.content
  )

  h.eq(
    "rs_0a10a8c968d594670168e91d0204ac8195b26b3e4de997f65c",
    adapter.handlers.response.parse_chat(adapter, json).output.reasoning.id
  )
  h.eq("gAAAAABo6", adapter.handlers.response.parse_chat(adapter, json).output.reasoning.encrypted_content)
end

T["Responses"]["Streaming"] = new_set()

T["Responses"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.response.parse_chat(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Elegant language", output)
end

T["Responses"]["Streaming"]["can process reasoning output"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_reasoning_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.response.parse_chat(adapter, line)
    if chat_output and chat_output.output and chat_output.output.reasoning and chat_output.output.reasoning.content then
      output = output .. chat_output.output.reasoning.content
    end
  end

  h.expect_starts_with("**Deciding on Ruby's description**", output)
end

T["Responses"]["Streaming"]["can process tools"] = function()
  -- Adds tool calls to the tools table
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openai_responses_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.response.parse_chat(adapter, line, tools)
  end

  local expected = {
    {
      call_id = "call_hvKk3FjuupQx8xeHeVbQNZkM",
      ["function"] = {
        arguments = '{"units":"celsius","location":"London, United Kingdom"}',
        name = "weather",
      },
      id = "fc_0cebe04c7f5006bd0068e827962aa8819592a7e51f7fa0d0b3",
      type = "function",
    },
    {
      call_id = "call_lzBOVwzUEAuTss7Gifvp1Rwi",
      ["function"] = {
        arguments = '{"units":"celsius","location":"Paris, France"}',
        name = "weather",
      },
      id = "fc_0cebe04c7f5006bd0068e827963dfc81958741d3a9f70c8a94",
      type = "function",
    },
  }

  h.eq(expected, tools)
end

return T
