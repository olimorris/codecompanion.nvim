local adapter
local messages
local response

local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

describe("Mistral adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("mistral")

    ---------------------------------------------------------- STREAMING OUTPUT
    messages = { {
      content = "Explain Ruby in two words",
      role = "user",
    } }

    response = {
      {
        request = [[data: {"id":"73d5e2bca442421e9c8c93ada114f58c","object":"chat.completion.chunk","created":1741809159,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}]],
        output = {
          content = "",
          role = "assistant",
        },
      },
      {
        request = [[data: {"id":"73d5e2bca442421e9c8c93ada114f58c","object":"chat.completion.chunk","created":1741809159,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":"Dynamic"},"finish_reason":null}]}]],
        output = {
          content = "Dynamic",
        },
      },
      {
        request = [[data: {"id":"73d5e2bca442421e9c8c93ada114f58c","object":"chat.completion.chunk","created":1741809159,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":" Typ"},"finish_reason":null}]}]],
        output = {
          content = " Typ",
        },
      },
      {
        request = [[data: {"id":"73d5e2bca442421e9c8c93ada114f58c","object":"chat.completion.chunk","created":1741809159,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":"ing"},"finish_reason":null}]}]],
        output = {
          content = "ing",
        },
      },
      {
        request = [[data: {"id":"73d5e2bca442421e9c8c93ada114f58c","object":"chat.completion.chunk","created":1741809159,"model":"mistral-small-latest","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":399,"total_tokens":402,"completion_tokens":3}}]],
        output = {
          content = "",
        },
      },
    }
    -------------------------------------------------------------------- // END
  end)

  it("can form messages to be sent to the API", function()
    h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    h.eq(
      { content = "Dynamic Typing", role = "assistant" },
      adapter_helpers.chat_buffer_output(response, adapter)
    )
  end)
end)

describe("Mistral adapter with NO STREAMING", function()
  before_each(function()
    response = {
      {
        request = {
          body = '{"id":"b48d82f02a6f469e984ee0dc438e99a2","object":"chat.completion","created":1741809694,"model":"mistral-small-latest","choices":[{"index":0,"message":{"role":"assistant","tool_calls":null,"content":"Dynamic Typing"},"finish_reason":"stop"}],"usage":{"prompt_tokens":399,"total_tokens":402,"completion_tokens":3}}',
          exit = 0,
          headers = {
            "date: Wed, 12 Mar 2025 20:01:35 GMT",
            "content-type: application/json",
          },
          status = 200,
        },
        output = {
          content = "Dynamic Typing",
          role = "assistant",
        },
      },
    }

    adapter = require("codecompanion.adapters").extend("mistral", {
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
