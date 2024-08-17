local adapter
local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

--------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
local messages = { {
  content = "Explain Ruby in two words",
  role = "user",
} }

local stream_response = {
  {
    request = [[{"model":"llama2","created_at":"2024-03-07T20:02:30.622386Z","message":{"role":"assistant","content":"\n"},"done":false}]],
    output = {
      content = "\n",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-07T20:02:30.652682Z","message":{"role":"assistant","content":"\""},"done":false}]],
    output = {
      content = '"',
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-07T20:02:30.681756Z","message":{"role":"assistant","content":"Be"},"done":false}]],
    output = {
      content = "Be",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-07T20:02:30.710758Z","message":{"role":"assistant","content":"aut"},"done":false}]],
    output = {
      content = "aut",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-07T20:02:30.739508Z","message":{"role":"assistant","content":"iful"},"done":false}]],
    output = {
      content = "iful",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-07T20:02:30.770345Z","message":{"role":"assistant","content":" Language"},"done":false}]],
    output = {
      content = " Language",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-07T20:02:30.7994Z","message":{"role":"assistant","content":"\""},"done":false}]],
    output = {
      content = '"',
      role = "assistant",
    },
  },
}

------------------------------------------------------------------------ // END

describe("Ollama adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").extend("ollama", {
      schema = {
        model = {
          default = "llama2",
          choices = { "llama2" },
        },
      },
    })
  end)

  it("can form messages to be sent to the API", function()
    assert.are.same({ messages = messages }, adapter.args.callbacks.form_messages(adapter, messages))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    assert.are.same(stream_response[#stream_response].output, helpers.chat_buffer_output(stream_response, adapter))
  end)
end)
