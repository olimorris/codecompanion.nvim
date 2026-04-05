local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Gemini adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("gemini")
    end,
  },
})

T["Gemini adapter"]["can form messages to be sent to the API"] = function()
  local messages = {
    {
      content = "Follow the user's request",
      role = "system",
    },
    {
      content = "Respond in code",
      role = "system",
    },
    {
      content = "Explain Ruby in two words",
      role = "user",
    },
  }

  local output = {
    contents = {
      {
        role = "user",
        parts = {
          { text = "Explain Ruby in two words" },
        },
      },
    },
    system_instruction = {
      parts = {
        { text = "Follow the user's request" },
        { text = "Respond in code" },
      },
      role = "user",
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

T["Gemini adapter"]["can form messages with system prompt"] = function()
  local messages = {
    {
      content = "You are a helpful assistant",
      role = "system",
    },
    {
      content = "hello",
      role = "user",
    },
    {
      content = "Hi, how can I help?",
      role = "model",
    },
  }

  local output = {
    contents = {
      {
        role = "user",
        parts = {
          { text = "hello" },
        },
      },
      {
        role = "model",
        parts = {
          { text = "Hi, how can I help?" },
        },
      },
    },
    system_instruction = {
      parts = {
        { text = "You are a helpful assistant" },
      },
      role = "user",
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

T["Gemini adapter"]["can form messages without system prompt"] = function()
  local messages = {
    {
      content = "hello",
      role = "user",
    },
    {
      content = "Hi, how can I help?",
      role = "model",
    },
  }

  local output = {
    contents = {
      {
        role = "user",
        parts = {
          { text = "hello" },
        },
      },
      {
        role = "model",
        parts = {
          { text = "Hi, how can I help?" },
        },
      },
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

T["Gemini adapter"]["can form messages with tool calls and responses"] = function()
  local messages = {
    {
      content = "What's the weather?",
      role = "user",
    },
    {
      role = "model",
      tools = {
        calls = {
          {
            _index = 1,
            id = "call_1",
            thought_signature = "Ev0BCvoBAb4",
            type = "function",
            ["function"] = {
              arguments = '{"location":"London"}',
              name = "weather",
            },
          },
        },
      },
    },
    {
      content = '{"temperature": 20}',
      role = "tool",
      tools = {
        call_id = "call_1",
        name = "weather",
      },
    },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  -- User message
  h.eq("user", output.contents[1].role)
  h.eq("What's the weather?", output.contents[1].parts[1].text)

  -- Model message with functionCall including id and thoughtSignature
  h.eq("model", output.contents[2].role)
  h.eq("weather", output.contents[2].parts[1].functionCall.name)
  h.eq({ location = "London" }, output.contents[2].parts[1].functionCall.args)
  h.eq("call_1", output.contents[2].parts[1].functionCall.id)
  h.eq("Ev0BCvoBAb4", output.contents[2].parts[1].thoughtSignature)

  -- Tool response with functionResponse including id
  h.eq("user", output.contents[3].role)
  h.eq("weather", output.contents[3].parts[1].functionResponse.name)
  h.eq({ temperature = 20 }, output.contents[3].parts[1].functionResponse.response)
  h.eq("call_1", output.contents[3].parts[1].functionResponse.id)
end

T["Gemini adapter"]["merges consecutive tool responses into one message"] = function()
  local messages = {
    {
      content = "Check weather in both cities",
      role = "user",
    },
    {
      role = "model",
      tools = {
        calls = {
          {
            _index = 1,
            id = "call_1",
            type = "function",
            ["function"] = { arguments = '{"location":"London"}', name = "weather" },
          },
          {
            _index = 2,
            id = "call_2",
            type = "function",
            ["function"] = { arguments = '{"location":"Paris"}', name = "weather" },
          },
        },
      },
    },
    {
      content = '{"temperature": 15}',
      role = "tool",
      tools = { call_id = "call_1", name = "weather" },
    },
    {
      content = '{"temperature": 18}',
      role = "tool",
      tools = { call_id = "call_2", name = "weather" },
    },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  -- Should be 3 entries: user, model (functionCalls), user (merged functionResponses)
  h.eq(3, #output.contents)
  h.eq("user", output.contents[3].role)
  h.eq(2, #output.contents[3].parts)
  h.eq("weather", output.contents[3].parts[1].functionResponse.name)
  h.eq("weather", output.contents[3].parts[2].functionResponse.name)
end

T["Gemini adapter"]["can form messages with tool call text content"] = function()
  local messages = {
    {
      content = "What's the weather?",
      role = "user",
    },
    {
      content = "I'll check the weather for you.",
      role = "model",
      tools = {
        calls = {
          {
            _index = 1,
            id = "call_1",
            type = "function",
            ["function"] = { arguments = '{"location":"London"}', name = "weather" },
          },
        },
      },
    },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  -- Model message should have both text and functionCall parts
  h.eq("model", output.contents[2].role)
  h.eq(2, #output.contents[2].parts)
  h.eq("I'll check the weather for you.", output.contents[2].parts[1].text)
  h.eq("weather", output.contents[2].parts[2].functionCall.name)
end

T["Gemini adapter"]["can handle concatenated tool arguments in form_messages"] = function()
  local messages = {
    {
      content = "Read files",
      role = "user",
    },
    {
      role = "model",
      tools = {
        calls = {
          {
            _index = 1,
            id = "call_1",
            type = "function",
            ["function"] = {
              arguments = '{"filepath":"1.md","start":0,"end":-1}{"filepath":"2.md","start":0,"end":-1}',
              name = "read_file",
            },
          },
        },
      },
    },
  }

  local output = adapter.handlers.form_messages(adapter, messages)
  local args = output.contents[2].parts[1].functionCall.args

  h.eq("1.md", args.filepath)
  h.eq(0, args.start)
  h.eq(-1, args["end"])
end

T["Gemini adapter"]["can form tools to be sent to the API"] = function()
  local weather = require("tests.interactions.chat.tools.builtin.stubs.weather").schema
  local tools = { weather = { weather } }

  local output = adapter.handlers.form_tools(adapter, tools)

  h.eq(1, #output.tools)
  h.eq(1, #output.tools[1].functionDeclarations)

  local decl = output.tools[1].functionDeclarations[1]
  h.eq("weather", decl.name)
  h.eq(weather["function"].description, decl.description)
  h.eq(weather["function"].parameters.type, decl.parameters.type)
  h.eq(weather["function"].parameters.properties, decl.parameters.properties)
  h.eq(weather["function"].parameters.required, decl.parameters.required)

  -- Gemini does not support additionalProperties or strict
  h.eq(nil, decl.parameters.additionalProperties)
  h.eq(nil, decl.parameters.strict)
end

T["Gemini adapter"]["can normalize tool calls via format_tool_calls"] = function()
  local raw_tools = {
    {
      _index = 1,
      args = { location = "London", units = "celsius" },
      name = "weather",
    },
  }

  local formatted = adapter.handlers.tools.format_tool_calls(adapter, raw_tools)

  h.eq(1, #formatted)
  h.eq(1, formatted[1]._index)
  h.eq("function", formatted[1].type)
  h.eq("weather", formatted[1]["function"].name)

  -- arguments should be a JSON string
  local decoded = vim.json.decode(formatted[1]["function"].arguments)
  h.eq("London", decoded.location)
  h.eq("celsius", decoded.units)
end

T["Gemini adapter"]["can format tool response via output_response"] = function()
  local tool_call = {
    id = "call_123",
    type = "function",
    ["function"] = { arguments = '{"location":"London"}', name = "weather" },
  }

  local result = adapter.handlers.tools.output_response(adapter, tool_call, '{"temperature": 20}')

  h.eq("tool", result.role)
  h.eq("weather", result.tools.name)
  h.eq("call_123", result.tools.call_id)
  h.eq('{"temperature": 20}', result.content)
end

T["Gemini adapter"]["Streaming"] = new_set()

T["Gemini adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Elegant, dynamic", output)
end

T["Gemini adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 1,
      args = { location = "London", units = "celsius" },
      id = "call_1",
      name = "weather",
    },
    {
      _index = 2,
      args = { location = "Paris", units = "celsius" },
      id = "call_2",
      name = "weather",
    },
  }

  h.eq(tool_output, tools)
end

T["Gemini adapter"]["Streaming"]["can skip thought parts and process tools"] = function()
  local tools = {}
  local text = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_tools_thought_streaming.txt")
  for _, line in ipairs(lines) do
    local result = adapter.handlers.chat_output(adapter, line, tools)
    if result and result.output.content then
      text = text .. result.output.content
    end
  end

  -- Should extract only the functionCall, not the thought text
  h.eq(1, #tools)
  h.eq("file_search", tools[1].name)
  h.eq({ query = "README.md" }, tools[1].args)

  -- Should capture id and thoughtSignature for round-tripping
  h.eq("abc123", tools[1].id)
  h.eq("Ev0BCvoBAb4", tools[1].thought_signature)

  -- Thought text should not appear in output
  h.eq("", text)
end

T["Gemini adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("gemini", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Gemini adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_no_streaming.txt")
  data = table.concat(data, "\n")

  local json = { body = data }

  h.expect_starts_with("Elegant, dynamic.", adapter.handlers.chat_output(adapter, json).output.content)
end

T["Gemini adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 1,
      args = { location = "London, UK", units = "celsius" },
      id = "call_1",
      name = "weather",
    },
    {
      _index = 2,
      args = { location = "Paris, France", units = "celsius" },
      id = "call_2",
      name = "weather",
    },
  }
  h.eq(tool_output, tools)
end

T["Gemini adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_no_streaming.txt")
  data = table.concat(data, "\n")

  local json = { body = data }

  h.expect_starts_with("Elegant, dynamic.", adapter.handlers.inline_output(adapter, json).output)
end

return T
