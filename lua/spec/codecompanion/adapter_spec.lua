local assert = require("luassert")

local Adapter = require("codecompanion.adapter")

local chat_buffer_settings = {
  frequency_penalty = 0,
  model = "gpt-4-0125-preview",
  presence_penalty = 0,
  temperature = 1,
  top_p = 1,
  stop = nil,
  max_tokens = nil,
  logit_bias = nil,
  user = nil,
}

describe("Adapter", function()
  it("can receive parameters from a chat buffer's settings", function()
    local adapter = require("codecompanion.adapters.openai")
    local result = adapter:set_params(chat_buffer_settings)

    -- The `stream` parameter is not present in the chat buffer's settings, so remove it to get the tests to pass
    result.parameters.stream = nil

    assert.are.same(chat_buffer_settings, result.parameters)
  end)
end)
