local assert = require("luassert")

local test_adapter = {
  name = "TestAdapter",
  url = "https://api.openai.com/v1/chat/completions",
  headers = {
    content_type = "application/json",
  },
  parameters = {
    stream = true,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters.data",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "gpt-4-0125-preview",
      choices = {
        "gpt-4-1106-preview",
        "gpt-4",
        "gpt-3.5-turbo-1106",
        "gpt-3.5-turbo",
      },
    },
    temperature = {
      order = 2,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 1,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 3,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 1,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
  },
}

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

  it("can nest parameters based on an adapter's schema", function()
    local adapter = require("codecompanion.adapter").new(test_adapter)
    local result = adapter:set_params(chat_buffer_settings)

    local expected = {
      stream = true,
      data = {
        model = "gpt-4-0125-preview",
      },
      options = {
        temperature = 1,
        top_p = 1,
      },
    }

    assert.are.same(expected, result.parameters)
  end)
end)
