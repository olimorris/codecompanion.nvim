local adapter = require("codecompanion.adapters.ollama")
local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

--------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
local messages = { {
  content = "Explain Ruby in two words",
  role = "user",
} }

local stream_response = {
  {
    request = [[{"model":"dolphin-mistral","created_at":"2024-03-07T20:02:30.622386Z","message":{"role":"assistant","content":"\n"},"done":false}]],
    output = {
      content = "\n",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"dolphin-mistral","created_at":"2024-03-07T20:02:30.652682Z","message":{"role":"assistant","content":"\""},"done":false}]],
    output = {
      content = '"',
      role = "assistant",
    },
  },
  {
    request = [[{"model":"dolphin-mistral","created_at":"2024-03-07T20:02:30.681756Z","message":{"role":"assistant","content":"Be"},"done":false}]],
    output = {
      content = "Be",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"dolphin-mistral","created_at":"2024-03-07T20:02:30.710758Z","message":{"role":"assistant","content":"aut"},"done":false}]],
    output = {
      content = "aut",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"dolphin-mistral","created_at":"2024-03-07T20:02:30.739508Z","message":{"role":"assistant","content":"iful"},"done":false}]],
    output = {
      content = "iful",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"dolphin-mistral","created_at":"2024-03-07T20:02:30.770345Z","message":{"role":"assistant","content":" Language"},"done":false}]],
    output = {
      content = " Language",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"dolphin-mistral","created_at":"2024-03-07T20:02:30.7994Z","message":{"role":"assistant","content":"\""},"done":false}]],
    output = {
      content = '"',
      role = "assistant",
    },
  },
}

local done_response =
  [[{"model":"dolphin-mistral","created_at":"2024-03-06T18:35:15.921631Z","message":{"role":"assistant","content":""},"done":true,"total_duration":6035327208,"load_duration":5654490167,"prompt_eval_count":26,"prompt_eval_duration":173338000,"eval_count":8,"eval_duration":205986000}]]
------------------------------------------------------------------------ // END

describe("Ollama adapter", function()
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
