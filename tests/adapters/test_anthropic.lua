local adapter
local messages
local response

local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

describe("Anthropic adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("anthropic")

    ----------------------------------------------- OUTPUT FROM THE CHAT BUFFER
    messages = { {
      content = "Explain Ruby in two words",
      role = "user",
    } }

    response = {
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
    -------------------------------------------------------------------- // END
  end)

  it("consolidates system prompts in their own block", function()
    messages = {
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
    messages = {
      { content = "Hello", role = "user" },
      { content = "World!", role = "user" },
      { content = "What up?!", role = "user" },
    }

    h.eq(
      { { role = "user", content = "Hello\n\nWorld!\n\nWhat up?!" } },
      adapter.handlers.form_messages(adapter, messages).messages
    )
  end)

  it("can output streamed data into a format for the chat buffer", function()
    h.eq({
      content = "Dynamic, elegant.",
      role = "assistant",
    }, adapter_helpers.chat_buffer_output(response, adapter))
  end)
end)

describe("Anthropic adapter with NO STREAMING", function()
  before_each(function()
    response = {
      {
        request = {
          body = '{"id":"msg_01NcyMmvGYa32CRkwFJLFZ42","type":"message","role":"assistant","model":"claude-3-5-sonnet-20241022","content":[{"type":"text","text":"Dynamic elegance\\n\\nWould you like me to explain what makes Ruby both dynamic and elegant?"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":439,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":21}}',
          exit = 0,
          headers = {
            "date: Sun, 09 Feb 2025 19:38:25 GMT",
            -- Deleted the rest
          },
          status = 200,
        },
        output = {
          content = "Dynamic elegance\n\nWould you like me to explain what makes Ruby both dynamic and elegant?",
          role = "assistant",
        },
      },
    }

    adapter = require("codecompanion.adapters").extend("anthropic", {
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
