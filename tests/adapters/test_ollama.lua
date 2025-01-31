local adapter
local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

local chat

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
          default = function()
            return "llama2"
          end,
          choices = { "llama2" },
        },
      },
    })
    chat, _ = h.setup_chat_buffer(nil, adapter)
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
    h.eq(stream_response[#stream_response].output, adapter_helpers.chat_buffer_output(stream_response, adapter))
  end)
end)
