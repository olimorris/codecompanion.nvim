local adapter
local messages
local response

local adapter_helpers = require("tests.adapters.helpers")
local h = require("tests.helpers")

describe("HuggingFace adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("huggingface")

    messages = { {
      content = "Explain Ruby in two words",
      role = "user",
    } }

    response = {
      {
        request = [[data: {"choices":[{"delta":{"role":"assistant","content":""}}]}]],
        output = {
          content = "",
          role = "assistant",
        },
      },
      {
        request = [[data: {"choices":[{"delta":{"content":"Dynamic"}}]}]],
        output = {
          content = "Dynamic",
        },
      },
      {
        request = [[data: {"choices":[{"delta":{"content":" elegance"}}]}]],
        output = {
          content = " elegance",
        },
      },
    }
  end)

  it("can form messages to be sent to the API", function()
    local formed_messages = adapter.handlers.form_messages(adapter, messages)
    h.eq({ messages = messages }, formed_messages)
  end)

  it("can output streamed data into a format for the chat buffer", function()
    local final_output = adapter_helpers.chat_buffer_output(response, adapter)
    h.eq(response[#response].output, final_output)
  end)
end)

describe("HuggingFace adapter headers", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("huggingface")
    adapter.parameters = {
      ["x-use-cache"] = "false",
      ["x-wait-for-model"] = "true",
    }
  end)

  it("sets custom headers correctly", function()
    local expected_headers = {
      ["Content-Type"] = "application/json",
      Authorization = "Bearer ${api_key}",
      ["x-use-cache"] = "false",
      ["x-wait-for-model"] = "true",
    }
    h.eq(expected_headers["x-use-cache"], adapter.parameters["x-use-cache"])
    h.eq(expected_headers["x-wait-for-model"], adapter.parameters["x-wait-for-model"])
  end)

  it("validates header parameter choices", function()
    h.eq(true, adapter.schema["x-use-cache"].choices[1] == "true")
    h.eq(true, adapter.schema["x-use-cache"].choices[2] == "false")
    h.eq(true, adapter.schema["x-wait-for-model"].choices[1] == "true")
    h.eq(true, adapter.schema["x-wait-for-model"].choices[2] == "false")
  end)
end)

describe("HuggingFace adapter with NO STREAMING", function()
  before_each(function()
    response = {
      {
        request = {
          body = [[{
            "choices": [{
              "message": {
                "role": "assistant",
                "content": "Dynamic elegance"
              },
              "finish_reason": "stop"
            }]
          }]],
          exit = 0,
          headers = {
            "date: Wed, 02 Oct 2024 17:06:07 GMT",
            "content-type: application/json",
          },
          status = 200,
        },
        output = {
          content = "Dynamic elegance",
          role = "assistant",
        },
      },
    }

    adapter = require("codecompanion.adapters").extend("huggingface", {
      opts = {
        stream = false,
      },
    })
  end)

  it("can output data into a format for the chat buffer", function()
    local output = adapter_helpers.chat_buffer_output(response, adapter)
    h.eq(response[#response].output, output)
  end)
end)

describe("HuggingFace adapter with system prompts", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("huggingface")
    messages = {
      {
        content = "You are a helpful assistant",
        role = "system",
      },
      {
        content = "Explain Ruby in two words",
        role = "user",
      },
    }
  end)

  it("can form messages with system prompts", function()
    local expected = {
      messages = {
        {
          role = "system",
          content = "You are a helpful assistant",
        },
        {
          role = "user",
          content = "Explain Ruby in two words",
        },
      },
    }
    local formed_messages = adapter.handlers.form_messages(adapter, messages)
    h.eq(expected, formed_messages)
  end)
end)

describe("HuggingFace adapter parameters", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("huggingface")
    adapter.parameters = {
      model = "meta-llama/Llama-2-70b-chat-hf",
      temperature = 0.7,
      max_tokens = 2048,
      top_p = 0.95,
      stream = true,
    }
  end)

  it("formats parameters correctly", function()
    messages = { { role = "user", content = "test" } }
    local params = adapter.handlers.form_parameters(adapter, adapter.parameters, messages)

    local expected = {
      model = "meta-llama/Llama-2-70b-chat-hf",
      temperature = 0.7,
      max_tokens = 2048,
      top_p = 0.95,
      stream = true,
    }
    h.eq(expected, params)
  end)
end)
