local assert = require("luassert")

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
  it("can form parameters from a chat buffer's settings", function()
    local adapter = require("codecompanion.adapters.openai")
    local result = adapter:set_params(chat_buffer_settings)

    -- Ignore this for now
    result.parameters.stream = nil

    assert.are.same(chat_buffer_settings, result.parameters)
  end)
end)
