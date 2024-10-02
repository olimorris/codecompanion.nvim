local adapter
local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

--------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
local messages = { {
  content = "Explain Ruby in two words",
  role = "user",
} }

local response = {
  {
    request = {
      body = '{\n  "id": "chatcmpl-ADx5bEkzrSB6WjrnB9ce1ofWcaOAq",\n  "object": "chat.completion",\n  "created": 1727888767,\n  "model": "gpt-4o-2024-05-13",\n  "choices": [\n    {\n      "index": 0,\n      "message": {\n        "role": "assistant",\n        "content": "Elegant simplicity.",\n        "refusal": null\n      },\n      "logprobs": null,\n      "finish_reason": "stop"\n    }\n  ],\n  "usage": {\n    "prompt_tokens": 343,\n    "completion_tokens": 3,\n    "total_tokens": 346,\n    "prompt_tokens_details": {\n      "cached_tokens": 0\n    },\n    "completion_tokens_details": {\n      "reasoning_tokens": 0\n    }\n  },\n  "system_fingerprint": "fp_5796ac6771"\n}',
      exit = 0,
      headers = {
        "date: Wed, 02 Oct 2024 17:06:07 GMT",
        "content-type: application/json",
        "access-control-expose-headers: X-Request-ID",
        "openai-organization: user-rl1mp5qrsyuposyh8rltuwfv",
        "openai-processing-ms: 122",
        "openai-version: 2020-10-01",
        "strict-transport-security: max-age=31536000; includeSubDomains; preload",
        "x-ratelimit-limit-requests: 500",
        "x-ratelimit-limit-tokens: 30000",
        "x-ratelimit-remaining-requests: 499",
        "x-ratelimit-remaining-tokens: 29590",
        "x-ratelimit-reset-requests: 120ms",
        "x-ratelimit-reset-tokens: 820ms",
        "x-request-id: req_912c1ceac92a7b39c4196b9aed7740f5",
        "cf-cache-status: DYNAMIC",
        "set-cookie: __cf_bm=QvvctMRZqTNce49DCrYcEAO0BHO.ruX2dIqAgs3JcVk-1727888767-1.0.1.1-K7N7KbpiBKffuGAOd5jnWK4cvNLtXdnpPOf8j62TdkJ6SOJMbXitIUxQ7FJQyREQyPOJWG77.dPVojKb0VdqaQ; path=/; expires=Wed, 02-Oct-24 17:36:07 GMT; domain=.api.openai.com; HttpOnly; Secure; SameSite=None",
        "x-content-type-options: nosniff",
        "set-cookie: _cfuvid=IfLqCirIk9nI0GNwfWer2Ivt2voLTBUvSMq0LDhCzXI-1727888767461-0.0.1.1-604800000; path=/; domain=.api.openai.com; HttpOnly; Secure; SameSite=None",
        "server: cloudflare",
        "cf-ray: 8cc647f9ec9c4141-LHR",
        "content-encoding: br",
        "",
        "",
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
    adapter = require("codecompanion.adapters").extend("openai", {
      opts = {
        stream = false,
      },
    })
  end)

  it("can output data into a format for the chat buffer", function()
    assert.are.same(response[#response].output, helpers.chat_buffer_output(response, adapter))
  end)
end)
