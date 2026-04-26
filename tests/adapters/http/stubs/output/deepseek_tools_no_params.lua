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
      content = "Let me check the weather for both locations.",
      role = "assistant",
      tool_calls = {
        {
          ["function"] = {
            arguments = "{}",
            name = "weather_with_default",
          },
          id = "call_00_YOblREljHrrLmGtaHE72LNh3",
          type = "function",
        },
        {
          ["function"] = {
            arguments = '{"location": "Paris, France", "units": "celsius"}',
            name = "weather_with_default",
          },
          id = "call_01_bKIQfFOpGabMlK7midnRZaBQ",
          type = "function",
        },
      },
    },
    {
      content = "Ran the weather tool The weather in London, UK is 15° celsius",
      role = "tool",
      tool_call_id = "call_00_YOblREljHrrLmGtaHE72LNh3",
    },
    {
      content = "Ran the weather tool The weather in Paris, France is 15° celsius",
      role = "tool",
      tool_call_id = "call_01_bKIQfFOpGabMlK7midnRZaBQ",
    },
  },
}
