local adapter = require("codecompanion.adapters.openai")
local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

--------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
local messages = { {
  content = "Explain Ruby in two words",
  role = "user",
} }

local stream_response = {
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

local done_response = "data: [DONE]"
------------------------------------------------------------------------ // END

describe("OpenAI adapter", function()
  it("can form messages to be sent to the API", function()
    assert.are.same({ messages = messages }, adapter.callbacks.form_messages(messages))
  end)

  it("can check if the streaming is complete", function()
    assert.is_true(adapter.callbacks.is_complete(done_response))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    assert.are.same(stream_response[#stream_response].output, helpers.chat_buffer_output(stream_response, adapter))
  end)
end)
