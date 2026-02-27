return {
  cache_control = {
    type = "ephemeral",
  },
  messages = {
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
          text = "I'll check the weather for both cities using Celsius units.",
          type = "text",
        },
        {
          id = "toolu_01QRThyzKt6NibK3m1DjUTkE",
          input = vim.empty_dict(),
          name = "weather_with_default",
          type = "tool_use",
        },
        {
          id = "toolu_015A1zQUwKw1YE3CYvRRUdXZ",
          input = {
            location = "Paris, France",
            units = "celsius",
          },
          name = "weather_with_default",
          type = "tool_use",
        },
      },
      role = "assistant",
    },
    {
      content = {
        {
          content = "Ran the weather tool The weather in London, UK is 15° celsius",
          is_error = false,
          tool_use_id = "toolu_01QRThyzKt6NibK3m1DjUTkE",
          type = "tool_result",
        },
        {
          content = "Ran the weather tool The weather in Paris, France is 15° celsius",
          is_error = false,
          tool_use_id = "toolu_015A1zQUwKw1YE3CYvRRUdXZ",
          type = "tool_result",
        },
      },
      role = "user",
    },
  },
  system = {
    {
      text = "default system prompt",
      type = "text",
    },
  },
}
