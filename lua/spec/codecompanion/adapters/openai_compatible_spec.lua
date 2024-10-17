local adapter
local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

-------------------------------------------------------------- STREAMING OUTPUT
local messages = { {
  content = "Explain Ruby in two words",
  role = "user",
} }

local response = {
  {
    request = [[data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}]],
    output = {
      content = "",
      role = "assistant",
    },
  },
  {
    request = [[data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":"Programming"},"logprobs":null,"finish_reason":null}]}]],
    output = {
      content = "Programming",
    },
  },
  {
    request = [[data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":" language"},"logprobs":null,"finish_reason":null}]}]],
    output = {
      content = " language",
    },
  },
}
------------------------------------------------------------------------ // END

describe("OpenAI compatible adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").extend("openai_compatible", {
      name = "llama3",
      env = {
        url = "http://127.0.0.1:11434",
        api_key = "keys",
      },
      schema = {
        model = {
          default = "llama-3.2-3b-instruct",
        },
        num_ctx = {
          default = 4096,
        },
      },
    })
  end)

  it("can form messages to be sent to the API", function()
    assert.are.same({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    assert.are.same(response[#response].output, helpers.chat_buffer_output(response, adapter))
  end)
end)

---------------------------------------------------------- NON-STREAMING OUTPUT
messages = { {
  content = "Explain Ruby in two words",
  role = "user",
} }

response = {
  {
    request = {
      body = '{\n  "id": "chatcmpl-ADx5bEkzrSB6WjrnB9ce1ofWcaOAq",\n  "object": "chat.completion",\n  "created": 1727888767,\n  "model": "gpt-4o-2024-05-13",\n  "choices": [\n    {\n      "index": 0,\n      "message": {\n        "role": "assistant",\n        "content": "Elegant simplicity.",\n        "refusal": null\n      },\n      "logprobs": null,\n      "finish_reason": "stop"\n    }\n  ],\n  "usage": {\n    "prompt_tokens": 343,\n    "completion_tokens": 3,\n    "total_tokens": 346,\n    "prompt_tokens_details": {\n      "cached_tokens": 0\n    },\n    "completion_tokens_details": {\n      "reasoning_tokens": 0\n    }\n  },\n  "system_fingerprint": "fp_5796ac6771"\n}',
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
------------------------------------------------------------------------ // END

describe("OpenAI adapter with NO STREAMING", function()
  before_each(function()
    adapter = require("codecompanion.adapters").extend("openai_compatible", {
      name = "llama3",
      env = {
        url = "http://127.0.0.1:11434",
        api_key = "keys",
      },
      schema = {
        model = {
          default = "llama-3.2-3b-instruct",
        },
        num_ctx = {
          default = 4096,
        },
      },
      opts = {
        stream = false,
      },
    })
  end)

  it("can output data into a format for the chat buffer", function()
    assert.are.same(response[#response].output, helpers.chat_buffer_output(response, adapter))
  end)
end)
