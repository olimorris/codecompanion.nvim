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
          _index = 0,
          ["function"] = {
            arguments = '{"location": "London", "units": "celsius"}',
            name = "weather",
          },
          id = "call_0_bb2a2194-a723-44a6-a1f8-bd05e9829eea",
          type = "function",
        },
        {
          _index = 1,
          ["function"] = {
            arguments = '{"location": "Paris", "units": "celsius"}',
            name = "weather",
          },
          id = "call_1_a460d461-60a7-468c-a699-ef9e2dced125",
          type = "function",
        },
      },
    },
    {
      content = "Ran the weather tool The weather in London is 15° celsius",
      role = "tool",
      tool_call_id = "call_0_bb2a2194-a723-44a6-a1f8-bd05e9829eea",
    },
    {
      content = "Ran the weather tool The weather in Paris is 15° celsius",
      role = "tool",
      tool_call_id = "call_1_a460d461-60a7-468c-a699-ef9e2dced125",
    },
  },
}
