local adapter
local messages
local response

local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

describe("DeepSeek adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("deepseek")
    ---------------------------------------------------------- STREAMING OUTPUT
    messages = { {
      content = "Explain Ruby in two words",
      role = "user",
    } }
    -------------------------------------------------------------------- // END
  end)

  it("can form messages to be sent to the API", function()
    h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
  end)

  it("merges consecutive messages with the same role", function()
    local input = {
      { role = "user", content = "A" },
      { role = "user", content = "B" },
      { role = "assistant", content = "C" },
      { role = "assistant", content = "D" },
      { role = "user", content = "E" },
    }

    local expected = {
      messages = {
        { role = "user", content = "A\n\nB" },
        { role = "assistant", content = "C\n\nD" },
        { role = "user", content = "E" },
      },
    }

    h.eq(expected, adapter.handlers.form_messages(adapter, input))
  end)

  it("merges system messages together at the start of the message chain", function()
    local input = {
      { role = "system", content = "System Prompt 1" },
      { role = "user", content = "User1" },
      { role = "system", content = "System Prompt 2" },
      { role = "system", content = "System Prompt 3" },
      { role = "assistant", content = "Assistant1" },
    }

    local expected = {
      messages = {
        { role = "system", content = "System Prompt 1\n\nSystem Prompt 2\n\nSystem Prompt 3" },
        { role = "user", content = "User1" },
        { role = "assistant", content = "Assistant1" },
      },
    }

    h.eq(expected, adapter.handlers.form_messages(adapter, input))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    local lines = vim.fn.readfile("tests/adapters/stubs/deepseek_streaming_output.txt")
    local output = ""
    for _, line in ipairs(lines) do
      output = output .. (adapter.handlers.chat_output(adapter, line).output.content or "")
    end
    h.eq(
      "Dynamic. Expressive.\n\nNext, you might ask about Ruby's key features or how it compares to other languages.",
      output
    )
  end)

  it("can handle reasoning content when streaming", function()
    -- adapter.handlers.setup(adapter)
    local lines = vim.fn.readfile("tests/adapters/stubs/deepseek_streaming_output.txt")
    local output = ""
    for _, line in ipairs(lines) do
      output = output .. (adapter.handlers.chat_output(adapter, line).output.reasoning or "")
    end
    h.expect_starts_with("Okay, the user wants me to explain Ruby in two words. ", output)
  end)
end)

describe("DeepSeek adapter with NO STREAMING", function()
  before_each(function()
    response = {
      {
        request = {
          body = '{\n  "id": "chatcmpl-ADx5bEkzrSB6WjrnB9ce1ofWcaOAq",\n  "object": "chat.completion",\n  "created": 1727888767,\n  "model": "deepseek-chat",\n  "choices": [\n    {\n      "index": 0,\n      "message": {\n        "role": "assistant",\n        "content": "Elegant simplicity.",\n        "refusal": null\n      },\n      "logprobs": null,\n      "finish_reason": "stop"\n    }\n  ],\n  "usage": {\n    "prompt_tokens": 343,\n    "completion_tokens": 3,\n    "total_tokens": 346,\n    "prompt_tokens_details": {\n      "cached_tokens": 0\n    },\n    "completion_tokens_details": {\n      "reasoning_tokens": 0\n    }\n  },\n  "system_fingerprint": "fp_5796ac6771"\n}',
          exit = 0,
          headers = {
            "date: Wed, 02 Oct 2024 17:06:07 GMT",
            "content-type: application/json",
          },
          status = 200,
        },
        output = {
          content = "Elegant simplicity.",
          role = "assistant",
        },
      },
    }

    adapter = require("codecompanion.adapters").extend("deepseek", {
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
