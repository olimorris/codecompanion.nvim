return {
  contents = {
    {
      parts = {
        {
          text = "What's the weather like in London and Paris?",
        },
      },
      role = "user",
    },
    {
      parts = {
        {
          functionCall = {
            args = vim.empty_dict(),
            id = "call_1",
            name = "weather_with_default",
          },
        },
        {
          functionCall = {
            args = {
              location = "Paris",
              units = "celsius",
            },
            id = "call_2",
            name = "weather_with_default",
          },
        },
      },
      role = "model",
    },
    {
      parts = {
        {
          functionResponse = {
            id = "call_1",
            name = "weather_with_default",
            response = {
              result = "Ran the weather tool The weather in London, UK is 15° celsius",
            },
          },
        },
        {
          functionResponse = {
            id = "call_2",
            name = "weather_with_default",
            response = {
              result = "Ran the weather tool The weather in Paris is 15° celsius",
            },
          },
        },
      },
      role = "user",
    },
  },
  system_instruction = {
    parts = {
      {
        text = "default system prompt",
      },
    },
    role = "user",
  },
}
