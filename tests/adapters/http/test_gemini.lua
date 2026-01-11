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
      content = "System Prompt 1",
      role = "system",
    },
    {
      content = "Explain Ruby in two words",
      role = "user",
    },
    {
      content = "System Prompt 2",
      role = "system",
    },
  }

  local output = {
    messages = {
      {
        content = "System Prompt 1 System Prompt 2",
        role = "system",
      },
      {
        content = "Explain Ruby in two words",
        role = "user",
      },
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

T["Gemini adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests.interactions.chat.tools.builtin.stubs.weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["Gemini adapter"]["Streaming"] = new_set()

T["Gemini adapter"]["Streaming"]["can build parameters"] = function()
  adapter.handlers.setup(adapter)
  h.eq({ stream = true, stream_options = { include_usage = true } }, adapter.parameters)
end

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
      ["function"] = {
        arguments = '{"units":"celsius","location":"London"}',
        name = "weather",
      },
      id = "call_1743628522_1",
      type = "function",
    },
    {
      _index = 2,
      ["function"] = {
        arguments = '{"units":"celsius","location":"Paris"}',
        name = "weather",
      },
      id = "call_1743628522_2",
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

T["Gemini adapter"]["Streaming"]["can preserve thought signatures in tool calls"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/http/stubs/gemini_tools_thought_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 1,
      ["function"] = {
        arguments = '{"query":"README.md"}',
        name = "file_search",
      },
      id = "function-call-13802169321809035407",
      type = "function",
      extra_content = {
        google = {
          thought_signature = "Eo123",
        },
      },
    },
  }

  h.eq(tool_output, tools)
end

T["Gemini adapter"]["Streaming"]["can send thought signatures back in messages"] = function()
  local messages = {
    {
      content = "Search for README.md",
      role = "user",
    },
    {
      role = "assistant",
      tools = {
        calls = {
          {
            _index = 1,
            id = "function-call-13802169321809035407",
            type = "function",
            ["function"] = {
              name = "file_search",
              arguments = '{"query":"README.md"}',
            },
            extra_content = {
              google = {
                thought_signature = "Eo123",
              },
            },
          },
        },
      },
    },
    {
      role = "user",
      tools = {
        call_id = "function-call-13802169321809035407",
      },
      content = '{"file":"README.md","contents":"..."}',
    },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  -- Verify the thought signature is preserved in the tool_calls
  local assistant_message = output.messages[2]
  h.eq("Eo123", assistant_message.tool_calls[1].extra_content.google.thought_signature)
end

T["Gemini adapter"]["Streaming"]["can fix concatenated tool arguments in message history"] = function()
  local messages = {
    {
      content = "Read all files",
      role = "user",
    },
    {
      role = "assistant",
      tools = {
        calls = {
          {
            _index = 1,
            id = "function-call-123",
            type = "function",
            ["function"] = {
              name = "read_file",
              arguments = '{"filepath":"1.md","start":0,"end":-1}{"filepath":"2.md","start":0,"end":-1}{"filepath":"3.md","start":0,"end":-1}',
            },
          },
        },
      },
    },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  -- Verify the concatenated arguments were cleaned to just the first object
  -- and that all fields from the first object are preserved
  local assistant_message = output.messages[2]
  local fixed_args = assistant_message.tool_calls[1]["function"]["arguments"]
  h.eq('{"filepath":"1.md","start":0,"end":-1}', fixed_args)

  -- Verify the fixed arguments are valid JSON with all expected fields
  local decoded = vim.json.decode(fixed_args)
  h.eq("1.md", decoded.filepath)
  h.eq(0, decoded.start)
  h.eq(-1, decoded["end"])
end

T["Gemini adapter"]["Streaming"]["can fix concatenated tool arguments in chat output"] = function()
  local tools = {
    {
      _index = 1,
      id = "function-call-456",
      type = "function",
      ["function"] = {
        name = "read_file",
        -- Gemini's bug: concatenates multiple JSON objects in streaming response
        arguments = '{"filepath":"test.lua","start":0,"end":-1}{"filepath":"other.lua","start":0,"end":-1}',
      },
    },
  }

  -- Process through chat_output to trigger the fix
  local data = 'data: {"choices":[{"delta":{},"index":0}]}\n\n'
  adapter.handlers.chat_output(adapter, data, tools)

  -- Verify the concatenated arguments were cleaned and all fields preserved
  local fixed_args = tools[1]["function"]["arguments"]
  h.eq('{"filepath":"test.lua","start":0,"end":-1}', fixed_args)

  -- Verify the fixed arguments are valid JSON with all expected fields
  local decoded = vim.json.decode(fixed_args)
  h.eq("test.lua", decoded.filepath)
  h.eq(0, decoded.start)
  h.eq(-1, decoded["end"])
end

T["Gemini adapter"]["Streaming"]["does not corrupt valid JSON with braces in strings"] = function()
  local tools = {
    {
      _index = 1,
      id = "function-call-789",
      type = "function",
      ["function"] = {
        name = "create_file",
        -- Valid JSON containing }{ inside a string value - should NOT be modified
        arguments = '{"filepath":"test.js","content":"function foo(){} { bar(); }"}',
      },
    },
  }

  local original_args = tools[1]["function"]["arguments"]

  -- Process through chat_output
  local data = 'data: {"choices":[{"delta":{},"index":0}]}\n\n'
  adapter.handlers.chat_output(adapter, data, tools)

  -- Verify the valid JSON was NOT modified
  h.eq(original_args, tools[1]["function"]["arguments"])

  -- Verify the arguments are still valid JSON with correct content
  local decoded = vim.json.decode(tools[1]["function"]["arguments"])
  h.eq("test.js", decoded.filepath)
  h.eq("function foo(){} { bar(); }", decoded.content)
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

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Elegant, dynamic.", adapter.handlers.chat_output(adapter, json).output.content)
end

T["Gemini adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_tools_no_streaming.txt")
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
      id = "call_1743631193_1",
      type = "function",
    },
    {
      _index = 2,
      ["function"] = {
        arguments = '{"units":"celsius","location":"Paris, France"}',
        name = "weather",
      },
      id = "call_1743631193_2",
      type = "function",
    },
  }
  h.eq(tool_output, tools)
end

T["Gemini adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/gemini_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Elegant, dynamic.", adapter.handlers.inline_output(adapter, json).output)
end

return T
