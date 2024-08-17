local adapter

local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

--------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
local messages = {
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

local stream_response = {
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

describe("Gemini adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("gemini")
  end)

  it("can form messages to be sent to the API", function()
    local adapter = require("codecompanion.adapters").extend("gemini")
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

    assert.are.same(output, adapter.args.callbacks.form_messages(adapter, messages))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    assert.are.same(stream_response[#stream_response].output, helpers.chat_buffer_output(stream_response, adapter))
  end)
end)
