local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Ollama adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("ollama", {
        schema = {
          model = {
            default = "llama3.1:latest",
          },
          choices = {
            "llama3.1:latest",
          },
          num_ctx = {
            default = 20000,
          },
        },
      })
    end,
  },
})

T["Ollama adapter"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["Ollama adapter"]["it can form messages with tools"] = function()
  local messages = {
    {
      role = "user",
      content = "What's the weather like in London and Paris?",
    },
    {
      role = "llm",
      tool_calls = {
        {
          ["function"] = {
            arguments = '{"location":"London, UK","units":"fahrenheit"}',
            name = "weather",
          },
          type = "function",
        },
        {
          ["function"] = {
            arguments = '{"location":"Paris, France","units":"fahrenheit"}',
            name = "weather",
          },
          type = "function",
        },
      },
    },
    {
      role = "tool",
      content = "Ran the weather tool **Tool Output**: The weather in London, UK is 15° fahrenheit",
    },
    {
      role = "tool",
      content = "Ran the weather tool **Tool Output**: The weather in Paris, France is 15° fahrenheit",
    },
  }

  local output = {
    messages = {
      {
        content = "What's the weather like in London and Paris?",
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
            type = "function",
          },
          {
            ["function"] = {
              arguments = '{"location":"Paris, France","units":"fahrenheit"}',
              name = "weather",
            },
            type = "function",
          },
        },
      },
      {
        content = "Ran the weather tool **Tool Output**: The weather in London, UK is 15° fahrenheit",
        role = "tool",
      },
      {
        content = "Ran the weather tool **Tool Output**: The weather in Paris, France is 15° fahrenheit",
        role = "tool",
      },
    },
  }

  -- Ensure that a content field is added to the messages
  local correct_messages = vim.deepcopy(messages)
  correct_messages[2].content = ""

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

T["Ollama adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests/strategies/chat/agents/tools/stubs/weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["Ollama adapter"]["Streaming"] = new_set()

T["Ollama adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/stubs/ollama_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.eq("**Dynamic Object-Oriented**", output)
end

T["Ollama adapter"]["Streaming"]["can form messages with images"] = function()
  local messages = {
    {
      content = "How are you?",
      role = "user",
    },
    {
      content = "I am fine, thanks. How can I help?",
      role = "assistant",
    },
    {
      content = "somefakebase64encoding",
      role = "user",
      opts = {
        mimetype = "image/jpg",
        reference = "<image>https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg</image>",
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
    {
      content = "How are you?",
      role = "user",
    },
    {
      content = "I am fine, thanks. How can I help?",
      role = "assistant",
    },
    {
      images = { "somefakebase64encoding" },
      role = "user",
    },
    {
      content = "What is this an image of?",
      role = "user",
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, messages).messages)
end

T["Ollama adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/stubs/ollama_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local expected_tool_output = {
    {
      ["function"] = {
        arguments = '{"units":"celsius","location":"London, UK"}',
        name = "weather",
      },
      type = "function",
    },
    {
      ["function"] = {
        arguments = '{"units":"fahrenheit","location":"Paris, FR"}',
        name = "weather",
      },
      type = "function",
    },
  }

  h.expect_json_equals(expected_tool_output[1]["function"]["arguments"], tools[1]["function"]["arguments"])
  h.expect_json_equals(expected_tool_output[2]["function"]["arguments"], tools[2]["function"]["arguments"])

  -- NOTE: the native ollama API adapter uses the openai format_tool_calls method, and it
  -- seems to work fine.
  --
  -- local formatted_tools = {
  --   {
  --     arguments = {
  --       location = "London, UK",
  --       units = "celsius",
  --     },
  --     name = "weather",
  --   },
  --   {
  --     arguments = {
  --       location = "Paris, FR",
  --       units = "fahrenheit",
  --     },
  --     name = "weather",
  --   },
  -- }
  --
  -- h.eq(formatted_tools, adapter.handlers.tools.format_tool_calls(adapter, tools))
end

T["Ollama adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("ollama", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Ollama adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/ollama_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic Scripting language", adapter.handlers.chat_output(adapter, json).output.content)
end

T["Ollama adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/ollama_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      ["function"] = {
        arguments = '{"location":"London, UK","units":"celsius"}',
        name = "weather",
      },
      type = "function",
    },
    {
      ["function"] = {
        arguments = '{"location":"Paris, FR","units":"fahrenheit"}',
        name = "weather",
      },
      type = "function",
    },
  }

  h.expect_json_equals(tool_output[1]["function"]["arguments"], tools[1]["function"]["arguments"])
  h.expect_json_equals(tool_output[2]["function"]["arguments"], tools[2]["function"]["arguments"])

  -- local formatted_tools = {
  --   {
  --     arguments = {
  --       location = "London, UK",
  --       units = "celsius",
  --     },
  --     name = "weather",
  --   },
  --   {
  --     arguments = {
  --       location = "Paris, FR",
  --       units = "fahrenheit",
  --     },
  --     name = "weather",
  --   },
  -- }
  --
  -- h.eq(formatted_tools, adapter.handlers.tools.format_tool_calls(adapter, tools))
end

T["Ollama adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/ollama_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic Scripting language", adapter.handlers.inline_output(adapter, json).output)
end

return T
