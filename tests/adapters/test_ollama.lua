local adapter
local messages
local response

local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

local chat

describe("Ollama adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("ollama")
    chat, _ = h.setup_chat_buffer(nil, adapter)

    --------------------------------------------------- OUTPUT FROM THE CHAT BUFFER
    messages = { {
      content = "Explain Ruby in two words",
      role = "user",
    } }

    response = {
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
  end)

  after_each(function()
    h.teardown_chat_buffer()
  end)

  it("correctly forms the settings", function()
    -- Equivalent to the chat:submit() method
    local params = adapter:map_schema_to_params(chat.settings).parameters
    h.eq({
      model = adapter.schema.model.default,
      options = {
        mirostat = 0,
        mirostat_eta = 0.1,
        mirostat_tau = 5,
        num_ctx = 2048,
        num_predict = -1,
        repeat_last_n = 64,
        repeat_penalty = 1.1,
        seed = 0,
        temperature = 0.8,
        tfs_z = 1,
        top_k = 40,
        top_p = 0.9,
      },
    }, params)

    -- Expands the model function
    h.eq(type(adapter.handlers.form_parameters(adapter, adapter:set_env_vars(params), messages).model), "string")
  end)

  it("can form messages to be sent to the API", function()
    h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
  end)

  it("can output streamed data into a format for the chat buffer", function()
    h.eq({
      content = '\n"Beautiful Language"',
      role = "assistant",
    }, adapter_helpers.chat_buffer_output(response, adapter))
  end)
end)

describe("Ollama adapter with NO STREAMING", function()
  before_each(function()
    response = {
      {
        request = {
          body = '{"model":"llama3.1:latest","created_at":"2025-02-09T21:59:27.81386Z","message":{"role":"assistant","content":"**Object-oriented**\\n**Dynamic**"},"done_reason":"stop","done":true,"total_duration":833897208,"load_duration":36003125,"prompt_eval_count":391,"prompt_eval_duration":567000000,"eval_count":8,"eval_duration":228000000}',
          exit = 0,
          headers = {
            "Content-Type: application/json; charset=utf-8",
            "Date: Sun, 09 Feb 2025 21:59:27 GMT",
            "Content-Length: 328",
            "",
            "",
          },
          status = 200,
        },
        output = {
          content = "**Object-oriented**\n**Dynamic**",
          role = "assistant",
        },
      },
    }

    adapter = require("codecompanion.adapters").extend("ollama", {
      opts = {
        stream = false,
      },
    })
  end)

  it("can output data into a format for the chat buffer", function()
    h.eq(response[#response].output, adapter_helpers.chat_buffer_output(response, adapter))
  end)
end)
