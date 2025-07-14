local h = require("tests.helpers")
local transform = require("codecompanion.utils.tool_transformers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Anthropic adapter"] = new_set({
  hooks = {
    pre_case = function()
      local codecompanion = require("codecompanion")
      adapter = require("codecompanion.adapters").resolve("anthropic")
    end,
  },
})

T["Anthropic adapter"]["form_messages"] = new_set()

T["Anthropic adapter"]["form_messages"]["consolidates system prompts in their own block"] = function()
  local messages = {
    { content = "Hello", role = "system" },
    { content = "What can you do?!", role = "user" },
    { content = "World", role = "system" },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  h.eq("Hello", output.system[1].text)
  h.eq("World", output.system[2].text)
  h.eq({
    {
      content = {
        {
          type = "text",
          text = "What can you do?!",
        },
      },
      role = "user",
    },
  }, output.messages)
end

T["Anthropic adapter"]["form_messages"]["regular chat"] = function()
  local input = {
    {
      content = "Explain Ruby in two words",
      role = "user",
      opts = {
        visible = true,
      },
      cycle = 1,
      id = 1849003275,
      some_made_up_thing = true,
    },
  }

  h.eq({
    messages = {
      {
        content = {
          {
            type = "text",
            text = "Explain Ruby in two words",
          },
        },
        role = "user",
      },
    },
  }, adapter.handlers.form_messages(adapter, input))
end

T["Anthropic adapter"]["form_messages"]["images"] = function()
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
      content = {
        {
          type = "text",
          text = "How are you?",
        },
      },
      role = "user",
    },
    {
      content = {
        {
          type = "text",
          text = "I am fine, thanks. How can I help?",
        },
      },
      role = "assistant",
    },
    {
      content = {
        {
          type = "image",
          source = {
            type = "base64",
            media_type = "image/jpg",
            data = "somefakebase64encoding",
          },
        },
        {
          type = "text",
          text = "What is this an image of?",
        },
      },
      role = "user",
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, messages).messages)
end

T["Anthropic adapter"]["form_messages"]["with tools and consecutive tool results"] = function()
  local input = {
    {
      content = "What's the weather like in London and Paris?",
      role = "user",
    },
    {
      content = "<thinking>To answer this question, I will: 1. Use the get_weather tool to get the current weather in San Francisco. 2. Use the get_time tool to get the current time in the America/Los_Angeles timezone, which covers London, UK.</thinking>",
      role = "assistant",
    },
    {
      role = "assistant",
      tool_calls = {
        {
          _index = 1,
          ["function"] = {
            arguments = '{"location": "London, UK", "units": "celsius"}',
            name = "weather",
          },
          id = "toolu_01A09q90qw90lq917835lq9",
          type = "function",
        },
      },
    },
    {
      role = "assistant",
      tool_calls = {
        {
          _index = 1,
          ["function"] = {
            arguments = '{"location": "Paris, France", "units": "celsius"}',
            name = "weather",
          },
          id = "toolu_01A09q90qw90lq917835lq8",
          type = "function",
        },
      },
    },
    {
      role = "tool",
      content = {
        type = "tool_result",
        content = "The weather in London is 15 degrees celsius",
        tool_use_id = "toolu_01A09q90qw90lq917835lq9",
        is_error = false,
      },
    },
    {
      role = "tool",
      content = {
        type = "tool_result",
        content = ". So enjoy it!",
        tool_use_id = "toolu_01A09q90qw90lq917835lq9",
        is_error = false,
      },
    },
    {
      role = "tool",
      content = {
        type = "tool_result",
        content = "The weather in Paris is 15 degrees celsius",
        tool_use_id = "toolu_01A09q90qw90lq917835lq8",
        is_error = false,
      },
    },
    {
      role = "user",
      content = "Thanks for the info!",
    },
  }

  local output = {
    {
      content = {
        {
          text = "What's the weather like in London and Paris?",
          type = "text",
        },
      },
      role = "user",
    },
    {
      content = {
        {
          text = "<thinking>To answer this question, I will: 1. Use the get_weather tool to get the current weather in San Francisco. 2. Use the get_time tool to get the current time in the America/Los_Angeles timezone, which covers London, UK.</thinking>",
          type = "text",
        },
        {
          id = "toolu_01A09q90qw90lq917835lq9",
          input = {
            location = "London, UK",
            units = "celsius",
          },
          name = "weather",
          type = "tool_use",
        },
        {
          id = "toolu_01A09q90qw90lq917835lq8",
          input = {
            location = "Paris, France",
            units = "celsius",
          },
          name = "weather",
          type = "tool_use",
        },
      },
      role = "assistant",
    },
    {
      content = {
        {
          content = "The weather in London is 15 degrees celsius. So enjoy it!",
          is_error = false,
          tool_use_id = "toolu_01A09q90qw90lq917835lq9",
          type = "tool_result",
        },
        {
          content = "The weather in Paris is 15 degrees celsius",
          is_error = false,
          tool_use_id = "toolu_01A09q90qw90lq917835lq8",
          type = "tool_result",
        },
        {
          text = "Thanks for the info!",
          type = "text",
        },
      },
      role = "user",
    },
  }

  h.eq({ messages = output }, adapter.handlers.form_messages(adapter, input))
end

T["Anthropic adapter"]["form_messages"]["handles tool results correctly"] = function()
  local messages = {
    {
      role = "user",
      content = "Use the weather tool to check London weather",
    },
    {
      role = "assistant",
      content = "I'll check the weather for you.",
      tool_calls = {
        {
          id = "call_123",
          ["function"] = {
            name = "get_weather",
            arguments = '{"location": "London"}',
          },
        },
      },
    },
    {
      role = "tool",
      content = {
        type = "tool_result",
        tool_use_id = "call_123",
        content = "London weather: 22°C, sunny",
        is_error = false,
      },
    },
  }

  local result = adapter.handlers.form_messages(adapter, messages)

  -- The tool result should be preserved as an array with the content intact
  local tool_message = result.messages[3]

  h.eq(tool_message.role, "user") -- Tool messages become user messages
  h.eq(type(tool_message.content), "table")
  h.eq(vim.islist(tool_message.content), true)
  h.eq(#tool_message.content, 1)
  h.eq(tool_message.content[1].type, "tool_result")
  h.eq(tool_message.content[1].tool_use_id, "call_123")
  h.eq(tool_message.content[1].content, "London weather: 22°C, sunny")
end

T["Anthropic adapter"]["form_messages"]["preserves separate tool results with different IDs"] = function()
  local messages = {
    {
      role = "user",
      content = {
        {
          type = "tool_result",
          tool_use_id = "call_123",
          content = "Weather data",
          is_error = false,
        },
        {
          type = "tool_result",
          tool_use_id = "call_456",
          content = "Calendar data",
          is_error = false,
        },
      },
    },
  }

  local result = adapter.handlers.form_messages(adapter, messages)

  -- The tool results should remain separate
  local user_message = result.messages[1]
  h.eq(#user_message.content, 2)
  h.eq(user_message.content[1].tool_use_id, "call_123")
  h.eq(user_message.content[2].tool_use_id, "call_456")
end

T["Anthropic adapter"]["form_messages"]["consolidates consecutive user messages together"] = function()
  local messages = {
    { content = "Hello", role = "user" },
    { content = "World!", role = "user" },
    { content = "What up?!", role = "user" },
  }

  h.eq({
    {
      content = {
        {
          text = "Hello",
          type = "text",
        },
        {
          text = "World!",
          type = "text",
        },
        {
          text = "What up?!",
          type = "text",
        },
      },
      role = "user",
    },
  }, adapter.handlers.form_messages(adapter, messages).messages)
end

T["Anthropic adapter"]["form_messages"]["can handle reasoning"] = function()
  local messages = {
    {
      content = "What's 2 + 2?",
      role = "user",
    },
    {
      content = "The answer is 4.",
      reasoning = {
        content = "I need to calculate 2 + 2. This is a basic arithmetic operation. 2 + 2 = 4.",
        _data = { signature = "mock_signature_12345" },
      },
      role = "assistant",
    },
  }

  local result = adapter.handlers.form_messages(adapter, messages)

  local expected = {
    {
      content = {
        {
          type = "text",
          text = "What's 2 + 2?",
        },
      },
      role = "user",
    },
    {
      content = {
        {
          type = "thinking",
          thinking = "I need to calculate 2 + 2. This is a basic arithmetic operation. 2 + 2 = 4.",
          signature = "mock_signature_12345",
        },
        {
          type = "text",
          text = "The answer is 4.",
        },
      },
      role = "assistant",
    },
  }

  h.eq({ messages = expected }, result)
end

T["Anthropic adapter"]["form_messages"]["tool use AND reasoning"] = function()
  local messages = {
    {
      role = "user",
      content = "What's the weather like in London?",
    },
    {
      role = "assistant",
      tool_calls = {
        {
          _index = 1,
          ["function"] = {
            arguments = '{"location": "London, UK", "units": "celsius"}',
            name = "weather",
          },
          id = "toolu_01UjbLnwyzbLtZNjvrDuiRDE",
          type = "function",
        },
      },
      reasoning = {
        content = "Some thinking block",
        _data = {
          signature = "some_signature",
        },
      },
    },
  }

  local result = adapter.handlers.form_messages(adapter, messages)

  local expected = {
    {
      content = {
        {
          type = "text",
          text = "What's the weather like in London?",
        },
      },
      role = "user",
    },
    {
      content = {
        {
          signature = "some_signature",
          thinking = "Some thinking block",
          type = "thinking",
        },
        {
          id = "toolu_01UjbLnwyzbLtZNjvrDuiRDE",
          input = {
            location = "London, UK",
            units = "celsius",
          },
          name = "weather",
          type = "tool_use",
        },
      },
      role = "assistant",
    },
  }

  h.eq({ messages = expected }, result)
end

T["Anthropic adapter"]["form_reasoning"] = function()
  local reasoning = {
    {
      content = "",
    },
    {
      content = "The user is asking if I'm",
    },
    {
      content = " working, which is a simple question to check if I'm functioning",
    },
    {
      content = " properly. This is a straightforward query that",
    },
    {
      content = " doesn't require any complex programming assistance or code",
    },
    {
      content = " analysis. I should give a brief, direct",
    },
    {
      content = " response confirming that I am functioning and ready to help with",
    },
    {
      content = " programming tasks.",
    },
    {
      signature = "EukDCkYIBRgCKkDwVZaI617wvi1+P9+q9M1lGFO7ZOgkmyHvC+qfGNa4/nkNcjoTlxrrCAufnzn1SzSATglo7KdHwTrKRxn5KvqcEgyRopWqnZT5GR4VknIaDDG+2FBu65H7US7/AyIw8NGN1o2Zu6WwxROgr7TeAQU+D54dm7lxXoGKI6sXdmLfe7YKSJNDywkyrs5gTGeuKtACKYLIfqA3hL8qmWgTo7anYIaUTLAcT8bCsj3Kcugbg7QZBbQmy+xHKdE22lPTIZZw5vIVb3urA0LLoBQ0TliqFf2qT7G9oMCsoukKFqYn4cHaQNGib4YJjY3SIKDw+xYpgiF6HMjl5lKyrNMwiM7ZZ41z4nOBMFSvCJWPP4kDmaQjBuKT6Wq8HcN6QJQP+0AbAnJe922U+C1W9pXV/fZSNGEkCIMqimHWLu2Ld4FtyIEVjZqTlNg3zbP9UGzWRmqg9nsNnMCdThdHHteEXv+hVfYY4amyXIQvUsKG+EM16Z+mZrLSTzH4oFd2J3q5J1M9NAMJpGD1abaqYeNXNGd7WCkXE8ZiVgbpVhyCFVID1U0y/Fr01JFj2DWuyg/nqKSToViwvxNuzj14s/Q9gL6phvmF5aekmDqrGq3ngJAIRfiKaZBXkFEgvdgmg5GNA031GAE=",
    },
  }

  local output = {
    content = "The user is asking if I'm working, which is a simple question to check if I'm functioning properly. This is a straightforward query that doesn't require any complex programming assistance or code analysis. I should give a brief, direct response confirming that I am functioning and ready to help with programming tasks.",
    _data = {
      signature = "EukDCkYIBRgCKkDwVZaI617wvi1+P9+q9M1lGFO7ZOgkmyHvC+qfGNa4/nkNcjoTlxrrCAufnzn1SzSATglo7KdHwTrKRxn5KvqcEgyRopWqnZT5GR4VknIaDDG+2FBu65H7US7/AyIw8NGN1o2Zu6WwxROgr7TeAQU+D54dm7lxXoGKI6sXdmLfe7YKSJNDywkyrs5gTGeuKtACKYLIfqA3hL8qmWgTo7anYIaUTLAcT8bCsj3Kcugbg7QZBbQmy+xHKdE22lPTIZZw5vIVb3urA0LLoBQ0TliqFf2qT7G9oMCsoukKFqYn4cHaQNGib4YJjY3SIKDw+xYpgiF6HMjl5lKyrNMwiM7ZZ41z4nOBMFSvCJWPP4kDmaQjBuKT6Wq8HcN6QJQP+0AbAnJe922U+C1W9pXV/fZSNGEkCIMqimHWLu2Ld4FtyIEVjZqTlNg3zbP9UGzWRmqg9nsNnMCdThdHHteEXv+hVfYY4amyXIQvUsKG+EM16Z+mZrLSTzH4oFd2J3q5J1M9NAMJpGD1abaqYeNXNGd7WCkXE8ZiVgbpVhyCFVID1U0y/Fr01JFj2DWuyg/nqKSToViwvxNuzj14s/Q9gL6phvmF5aekmDqrGq3ngJAIRfiKaZBXkFEgvdgmg5GNA031GAE=",
    },
  }

  h.eq(output, adapter.handlers.form_reasoning(adapter, reasoning))
end

T["Anthropic adapter"]["form_tools"] = function()
  local weather = require("tests/strategies/chat/agents/tools/stubs/weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { transform.to_anthropic(weather) } }, adapter.handlers.form_tools(adapter, tools))
end

T["Anthropic adapter"]["Non-Reasoning models have less tokens"] = function()
  local non_reasoning = require("codecompanion.adapters").extend("anthropic", {
    schema = {
      model = {
        default = "claude-3-5-sonnet-20241022",
      },
    },
  })
  local output = require("codecompanion.adapters").resolve(non_reasoning)
  h.eq(4096, output.schema.max_tokens.default(non_reasoning))
end

T["Anthropic adapter"]["Reasoning models have more tokens"] = function()
  local reasoning = require("codecompanion.adapters").extend("anthropic", {
    schema = {
      model = {
        default = "claude-3-7-sonnet-20250219",
      },
    },
  })
  local output = require("codecompanion.adapters").resolve(reasoning)
  h.eq(17000, output.schema.max_tokens.default(reasoning))
end

T["Anthropic adapter"]["Streaming"] = new_set()

T["Anthropic adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/stubs/anthropic_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Dynamic elegance", output)
end

T["Anthropic adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/stubs/anthropic_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "London, UK", "units": "celsius"}',
        name = "weather",
      },
      id = "toolu_01QRThyzKt6NibK3m1DjUTkE",
      type = "function",
    },
    {
      _index = 2,
      ["function"] = {
        arguments = '{"location": "Paris, France", "units": "celsius"}',
        name = "weather",
      },
      id = "toolu_015A1zQUwKw1YE3CYvRRUdXZ",
      type = "function",
    },
  }

  tools = adapter.handlers.tools.format_tool_calls(adapter, tools)

  h.eq(tool_output, tools)
end

T["Anthropic adapter"]["Streaming"]["can process reasoning output"] = function()
  local output = {
    content = "",
    reasoning = {
      content = "",
    },
  }
  local lines = vim.fn.readfile("tests/adapters/stubs/anthropic_reasoning_streaming.txt")
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

  h.expect_starts_with("**Elegant simplicity**", output.content)
  h.expect_starts_with("The user is asking me to describe the Ruby programming language", output.reasoning.content)
end

T["Anthropic adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("anthropic", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Anthropic adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Dynamic elegance", adapter.handlers.chat_output(adapter, json).output.content)
end

T["Anthropic adapter"]["No Streaming"]["can output for the inline assistant with non reasoning models"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Dynamic elegance", adapter.handlers.inline_output(adapter, json).output)
end

T["Anthropic adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 2,
      ["function"] = {
        arguments = '{"location": "London, UK", "units": "celsius"}',
        name = "weather",
      },
      id = "toolu_01TSJjnB81vBBT8dhP3tTCaM",
      type = "function",
    },
    {
      _index = 3,
      ["function"] = {
        arguments = '{"location": "Paris, France", "units": "celsius"}',
        name = "weather",
      },
      id = "toolu_01UEd4jZFvj5gdqyL1L7QTqg",
      type = "function",
    },
  }

  tools = adapter.handlers.tools.format_tool_calls(adapter, tools)

  h.expect_json_equals(tool_output[1]["function"]["arguments"], tools[1]["function"]["arguments"])
  h.expect_json_equals(tool_output[2]["function"]["arguments"], tools[2]["function"]["arguments"])
end

T["Anthropic adapter"]["No Streaming"]["can output for the inline assistant with reasoning models"] = function()
  adapter = require("codecompanion.adapters").extend("anthropic", {
    opts = {
      stream = false,
      can_reason = true,
    },
  })

  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_reasoning_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    [[<response>\n  <code>hello world</code>\n  <language>lua</language>\n  <placement>add</placement>\n</response>]],
    adapter.handlers.inline_output(adapter, json).output
  )
end

return T
