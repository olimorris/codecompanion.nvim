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
        request = [[data: {"id":"4f8c2452d38241219662c71bffdd4581","object":"chat.completion.chunk","created":1739718831,"model":"mistral-large-latest","choices":[{"index":0,"delta":{"content":""},"finish_reason":null}]}]],
        output = {
          content = "",
          role = "assistant",
        },
      },
      {
        request = [[data: {"id":"4f8c2452d38241219662c71bffdd4581","object":"chat.completion.chunk","created":1739718831,"model":"mistral-large-latest","choices":[{"index":0,"delta":{"content":"Object"},"finish_reason":null}]}]],
        output = {
          content = "Object",
        },
      },
      {
        request = [[data: {"id":"4f8c2452d38241219662c71bffdd4581","object":"chat.completion.chunk","created":1739718831,"model":"mistral-large-latest","choices":[{"index":0,"delta":{"content":"-"},"finish_reason":null}]}]],
        output = {
          content = "-",
        },
      },
      {
        request = [[data: {"id":"4f8c2452d38241219662c71bffdd4581","object":"chat.completion.chunk","created":1739718831,"model":"mistral-large-latest","choices":[{"index":0,"delta":{"content":"Oriented"},"finish_reason":null}]}]],
        output = {
          content = "Oriented",
        },
      },
      {
        request = [[data: {"id":"4f8c2452d38241219662c71bffdd4581","object":"chat.completion.chunk","created":1739718831,"model":"mistral-large-latest","choices":[{"index":0,"delta":{"content":" Programming"},"finish_reason":null}]}]],
        output = {
          content = " Programming",
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
      { content = "Object-Oriented Programming", role = "assistant" },
      adapter_helpers.chat_buffer_output(response, adapter)
    )
  end)
end)

describe("Mistral adapter with NO STREAMING", function()
  before_each(function()
    response = {
      {
        request = {
          body = '{\n "id":"9dc1b04f00d844a687aa93fa28ca5c95",\n "object":"chat.completion",\n "created":1739718775,\n "model":"mistral-large-latest",\n "choices":[\n {\n "index":0,\n "message":{\n "role":"assistant",\n "tool_calls":null,\n "content":"Object-Oriented Programming.\n\n(If you\'re looking for two words that describe Ruby more uniquely, consider: "Elegant Syntax")"\n },\n "finish_reason":"stop"\n },\n ],\n "usage":{\n "prompt_tokens":18,\n "total_tokens":53,\n "completion_tokens":35\n }\n }\n',
          exit = 0,
          headers = {
            "date: Sun, 16 Feb 2025 15:12:55 GMT",
            "content-type: application/json",
          },
          status = 200,
        },
        output = {
          content = 'Object-Oriented Programming.\n\n(If you\'re looking for two words that describe Ruby more uniquely, consider: "Elegant Syntax")',
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
end)
