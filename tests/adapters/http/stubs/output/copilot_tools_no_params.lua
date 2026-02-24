return {
  messages = {
    {
      content = "default system prompt",
      copilot_cache_control = {
        type = "ephemeral",
      },
      role = "system",
    },
    {
      content = "What's the weather like in London and Paris?",
      copilot_cache_control = {
        type = "ephemeral",
      },
      role = "user",
    },
    {
      role = "assistant",
      tool_calls = {
        {
          ["function"] = {
            arguments = "",
            name = "weather_with_default",
          },
          id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
          type = "function",
        },
        {
          ["function"] = {
            arguments = '{"location": "Paris", "units": "celsius"}',
            name = "weather_with_default",
          },
          id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
          type = "function",
        },
      },
    },
    {
      content = "Ran the weather tool The weather in London, UK is 15° celsius",
      copilot_cache_control = {
        type = "ephemeral",
      },
      role = "tool",
      tool_call_id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
    },
    {
      content = "Ran the weather tool The weather in Paris is 15° celsius",
      copilot_cache_control = {
        type = "ephemeral",
      },
      role = "tool",
      tool_call_id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
    },
  },
}
