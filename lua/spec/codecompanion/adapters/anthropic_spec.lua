local adapter = require("codecompanion.adapters.anthropic")
local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

--------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
local messages = { {
  content = "Explain Ruby in two words",
  role = "user",
} }

local stream_response = {
  {
    request = [[data: {"type":"message_start","message":{"id":"msg_01Ngmyfn49udNhWaojMVKiR6","type":"message","role":"assistant","content":[],"model":"claude-3-opus-20240229","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":13,"output_tokens":1}}}]],
    output = {
      content = "",
      role = "assistant",
    },
  },
  {
    request = [[data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Dynamic"}}]],
    output = {
      content = "Dynamic",
    },
  },
  {
    request = [[data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":","}}]],
    output = {
      content = ",",
    },
  },
  {
    request = [[data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" elegant"}}]],
    output = {
      content = " elegant",
    },
  },
  {
    request = [[data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"."}}]],
    output = {
      content = ".",
    },
  },
}

local error_response =
  [[data: {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Claude API. Please go to Plans & Billing to upgrade or purchase credits."}}]]
------------------------------------------------------------------------ // END

describe("Anthropic adapter", function()
  it("can form messages to be sent to the API", function()
    assert.are.same({ messages = messages }, adapter.callbacks.form_messages(adapter, messages))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    assert.are.same(stream_response[#stream_response].output, helpers.chat_buffer_output(stream_response, adapter))
  end)

  it("can handle errors", function()
    assert.are.same({
      status = "error",
      output = "Your credit balance is too low to access the Claude API. Please go to Plans & Billing to upgrade or purchase credits.",
    }, adapter.callbacks.chat_output(error_response))
  end)
end)
