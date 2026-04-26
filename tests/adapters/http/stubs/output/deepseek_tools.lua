return {
  messages = {
    {
      content = "default system prompt",
      role = "system",
    },
    {
      content = "What's the weather like in London and Paris?",
      role = "user",
    },
    {
      content = "",
      role = "assistant",
      tool_calls = {
        {
          ["function"] = {
            arguments = '{"location": "London, UK", "units": "celsius"}',
            name = "weather",
          },
          id = "call_00_xzVVyar4M7TXmqAvwt5lz3v2",
          type = "function",
        },
        {
          ["function"] = {
            arguments = '{"location": "Paris, France", "units": "celsius"}',
            name = "weather",
          },
          id = "call_01_FiLq2fgCjbR43jdNrxI4OYGD",
          type = "function",
        },
      },
    },
    {
      content = "Ran the weather tool The weather in London, UK is 15° celsius",
      role = "tool",
      tool_call_id = "call_00_xzVVyar4M7TXmqAvwt5lz3v2",
    },
    {
      content = "Ran the weather tool The weather in Paris, France is 15° celsius",
      role = "tool",
      tool_call_id = "call_01_FiLq2fgCjbR43jdNrxI4OYGD",
    },
  },
}
