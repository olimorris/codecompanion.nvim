local adapter = require("codecompanion.adapters.anthropic")
local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

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

------------------------------------------------------------------------ // END

describe("Anthropic adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("anthropic")
  end)

  it("consolidates system prompts in their own block", function()
    local messages = {
      { content = "Hello", role = "system" },
      { content = "World", role = "system" },
      { content = "What can you do?!", role = "user" },
    }

    local output = adapter.handlers.form_messages(adapter, messages)

    h.eq("Hello", output.system[1].text)
    h.eq("World", output.system[2].text)
    h.eq({ { content = "What can you do?!", role = "user" } }, output.messages)
  end)

  it("can form messages to be sent to the API", function()
    h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
  end)

  it("consolidates consecutive user messages together", function()
    local messages = {
      { content = "Hello", role = "user" },
      { content = "World!", role = "user" },
      { content = "What up?!", role = "user" },
    }

    h.eq(
      { { role = "user", content = "Hello World! What up?!" } },
      adapter.handlers.form_messages(adapter, messages).messages
    )
  end)

  it("can output streamed data into a format for the chat buffer", function()
    h.eq(stream_response[#stream_response].output, adapter_helpers.chat_buffer_output(stream_response, adapter))
  end)
end)
