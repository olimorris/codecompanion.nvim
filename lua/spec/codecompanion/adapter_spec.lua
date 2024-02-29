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

local openai_adapter = {
  url = "https://api.openai.com/v1/chat/completions",
  headers = {
    content_type = "application/json",
    Authorization = "Bearer ", -- ignore the API key for now
  },
  payload = {
    stream = true,
    model = "${model}",
    temperature = "${temperature}",
    top_p = "${top_p}",
    stop = "${stop}",
    max_tokens = "${max_tokens}",
    presence_penalty = "${presence_penalty}",
    frequency_penalty = "${frequency_penalty}",
    logit_bias = "${logit_bias}",
    user = "${user}",
  },
  schema = {
    model = {
      order = 1,
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
      type = "number",
      optional = true,
      default = 1,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    stop = {
      order = 4,
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Up to 4 sequences where the API will stop generating further tokens.",
      validate = function(l)
        return #l >= 1 and #l <= 4, "Must have between 1 and 4 elements"
      end,
    },
    max_tokens = {
      order = 5,
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    presence_penalty = {
      order = 6,
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    frequency_penalty = {
      order = 7,
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    logit_bias = {
      order = 8,
      type = "map",
      optional = true,
      default = nil,
      desc = "Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID) to an associated bias value from -100 to 100. Use https://platform.openai.com/tokenizer to find token IDs.",
      subtype_key = {
        type = "integer",
      },
      subtype = {
        type = "integer",
        validate = function(n)
          return n >= -100 and n <= 100, "Must be between -100 and 100"
        end,
      },
    },
    user = {
      order = 9,
      type = "string",
      optional = true,
      default = nil,
      desc = "A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. Learn more.",
      validate = function(u)
        return u:len() < 100, "Cannot be longer than 100 characters"
      end,
    },
  },
}

describe("Adapter", function()
  it("can form a payload consisting of a chat buffer's settings", function()
    local adapter = vim.deepcopy(openai_adapter)
    local result = Adapter.new(adapter):process(chat_buffer_settings)

    -- Remove the stream key from the payload as this isn't handled via the settings in the chat buffer
    result.payload.stream = nil

    assert.are.same(chat_buffer_settings, result.payload)
  end)
end)
