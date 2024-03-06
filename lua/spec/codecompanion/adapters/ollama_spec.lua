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
    request = [[{"model":"llama2","created_at":"2024-03-06T18:35:15.715665Z","message":{"role":"assistant","content":"\n"},"done":false}]],
    output = {
      content = "\n",
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-06T18:35:15.745213Z","message":{"role":"assistant","content":"\""},"done":false}]],
    output = {
      content = '\n"',
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-06T18:35:15.77473Z","message":{"role":"assistant","content":"E"},"done":false}]],
    output = {
      content = '\n"E',
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-06T18:35:15.803753Z","message":{"role":"assistant","content":"asy"},"done":false}]],
    output = {
      content = '\n"Easy',
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-06T18:35:15.833925Z","message":{"role":"assistant","content":" Program"},"done":false}]],
    output = {
      content = '\n"Easy Program',
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-06T18:35:15.862917Z","message":{"role":"assistant","content":"ming"},"done":false}]],
    output = {
      content = '\n"Easy Programming',
      role = "assistant",
    },
  },
  {
    request = [[{"model":"llama2","created_at":"2024-03-06T18:35:15.892319Z","message":{"role":"assistant","content":"\""},"done":false}]],
    output = {
      content = '\n"Easy Programming"',
      role = "assistant",
    },
  },
}

local done_response =
  [[{"model":"llama2","created_at":"2024-03-06T18:35:15.921631Z","message":{"role":"assistant","content":""},"done":true,"total_duration":6035327208,"load_duration":5654490167,"prompt_eval_count":26,"prompt_eval_duration":173338000,"eval_count":8,"eval_duration":205986000}]]
------------------------------------------------------------------------ // END

describe("Ollama adapter", function()
  it("can form messages to be sent to the API", function()
    assert.are.same({ messages = messages }, adapter.callbacks.form_messages(messages))
  end)

  it("can check if the streaming is complete", function()
    local data = adapter.callbacks.format_data(done_response)

    assert.is_true(adapter.callbacks.is_complete(data))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    assert.are.same(
      stream_response[#stream_response].output,
      helpers.chat_buffer_output(stream_response, adapter, messages)
    )
  end)
end)
