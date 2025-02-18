local adapter
local messages
local response

local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

describe("Gemini adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("gemini")

    --------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
    messages = {
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

    response = {
      {
        request = [[data: {"candidates": [{"content": {"parts": [{"text": "Object"}],"role": "model"},"finishReason": "STOP","index": 0}],"usageMetadata": {"promptTokenCount": 323,"candidatesTokenCount": 1,"totalTokenCount": 324}}]],
        output = {
          content = "Object",
          role = "llm",
        },
      },
      {
        request = [[data: {"candidates": [{"content": {"parts": [{"text": "-oriented scripting.\n\nNext: What is the difference between Ruby and Python?"}],"role": "model"},"finishReason": "STOP","index": 0,"safetyRatings": [{"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT","probability": "NEGLIGIBLE"},{"category": "HARM_CATEGORY_HATE_SPEECH","probability": "NEGLIGIBLE"},{"category": "HARM_CATEGORY_HARASSMENT","probability": "NEGLIGIBLE"},{"category": "HARM_CATEGORY_DANGEROUS_CONTENT","probability": "NEGLIGIBLE"}]}],"usageMetadata": {"promptTokenCount": 323,"candidatesTokenCount": 17,"totalTokenCount": 340}}]],
        output = {
          content = "-oriented scripting.\n\nNext: What is the difference between Ruby and Python?",
          role = "llm",
        },
      },
    }
    ------------------------------------------------------------------------ // END
  end)

  it("can form messages to be sent to the API", function()
    adapter = require("codecompanion.adapters").extend("gemini")
    local output = {
      system_instruction = {
        role = "user",
        parts = {
          { text = "Follow the user's request" },
          { text = "Respond in code" },
        },
      },
      contents = {
        {
          role = "user",
          parts = {
            { text = "Explain Ruby in two words" },
          },
        },
      },
    }

    h.eq(output, adapter.handlers.form_messages(adapter, messages))
  end)

  it("can form messages with system prompt", function()
    adapter = require("codecompanion.adapters").extend("gemini")
    local messages_with_system = {
      {
        content = "You are a helpful assistant",
        role = "system",
        id = 1,
        cycle = 1,
        opts = { visible = false },
      },
      {
        content = "hello",
        id = 2,
        opts = { visible = true },
        role = "user",
      },
      {
        content = "Hi, how can I help?",
        id = 3,
        opts = { visible = true },
        role = "llm",
      },
    }

    local output = {
      system_instruction = {
        role = "user",
        parts = {
          { text = "You are a helpful assistant" },
        },
      },
      contents = {
        {
          role = "user",
          parts = {
            { text = "hello" },
          },
        },
        {
          role = "user",
          parts = {
            { text = "Hi, how can I help?" },
          },
        },
      },
    }

    h.eq(output, adapter.handlers.form_messages(adapter, messages_with_system))
  end)

  it("can form messages without system prompt", function()
    adapter = require("codecompanion.adapters").extend("gemini")
    local messages_without_system = {
      {
        content = "hello",
        id = 1,
        opts = { visible = true },
        role = "user",
      },
      {
        content = "Hi, how can I help?",
        id = 2,
        opts = { visible = true },
        role = "llm",
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
          role = "user",
          parts = {
            { text = "Hi, how can I help?" },
          },
        },
      },
    }

    h.eq(output, adapter.handlers.form_messages(adapter, messages_without_system))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    h.eq({
      content = "Object-oriented scripting.\n\nNext: What is the difference between Ruby and Python?",
      role = "llm",
    }, adapter_helpers.chat_buffer_output(response, adapter))
  end)
end)

describe("Gemini adapter with NO STREAMING", function()
  before_each(function()
    response = {
      {
        request = {
          body = '{\n  "candidates": [\n    {\n      "content": {\n        "parts": [\n          {\n            "text": "Elegant, dynamic.\\n\\nWhat can I help you with next?\\n"\n          }\n        ],\n        "role": "model"\n      },\n      "finishReason": "STOP",\n      "avgLogprobs": -0.15357250826699392\n    }\n  ],\n  "usageMetadata": {\n    "promptTokenCount": 405,\n    "candidatesTokenCount": 14,\n    "totalTokenCount": 419,\n    "promptTokensDetails": [\n      {\n        "modality": "TEXT",\n        "tokenCount": 405\n      }\n    ],\n    "candidatesTokensDetails": [\n      {\n        "modality": "TEXT",\n        "tokenCount": 14\n      }\n    ]\n  },\n  "modelVersion": "gemini-2.0-flash"\n}',
          exit = 0,
          headers = {
            "content-type: application/json; charset=UTF-8",
          },
          status = 200,
        },
        output = {
          content = "Elegant, dynamic.\n\nWhat can I help you with next?\n",
          role = "llm",
        },
      },
    }

    adapter = require("codecompanion.adapters").extend("gemini", {
      opts = {
        stream = false,
      },
    })
  end)

  it("can output data into a format for the chat buffer", function()
    h.eq(response[#response].output, adapter_helpers.chat_buffer_output(response, adapter))
  end)

  it("can output data into a format for the inline assistant", function()
    h.eq(response[#response].output.content, adapter_helpers.inline_buffer_output(response, adapter))
  end)
end)
