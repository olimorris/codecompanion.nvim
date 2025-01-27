local h = require("tests.helpers")

local utils = require("codecompanion.utils.adapters")

local test_adapter = {
  name = "TestAdapter",
  url = "https://api.testgenai.com/v1/chat/completions",
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

local test_adapter2 = {
  name = "TestAdapter2",
  url = "https://api.oli.ai/v1/chat/${model}",
  env = {
    home = "HOME",
    model = "schema.model.default",
  },
  parameters = {
    stream = true,
  },
  headers = {
    content_type = "application/json",
    home = "${home}",
  },
  schema = {
    model = {
      order = 1,
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "oli_model_v2",
    },
    temperature = {
      default = "${home}",
      mapping = "parameters.temperature",
    },
  },
}

describe("Adapter", function()
  it("can form parameters from a chat buffer's settings", function()
    local adapter = require("codecompanion.adapters").extend("openai")
    local result = adapter:map_schema_to_params(chat_buffer_settings)

    -- Ignore this for now
    result.parameters.stream = nil
    result.parameters.stream_options = nil

    h.eq(chat_buffer_settings, result.parameters)
  end)

  it("can nest parameters based on an adapter's schema", function()
    local adapter = require("codecompanion.adapters").extend(test_adapter)
    local result = adapter:map_schema_to_params(chat_buffer_settings)

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

    h.eq(expected, result.parameters)
  end)

  it("can form environment variables", function()
    local adapter = require("codecompanion.adapters").extend(test_adapter2)
    local result = adapter:get_env_vars()

    h.eq(test_adapter2.schema.model.default, result.env_replaced.model)
    h.eq(os.getenv("HOME"), result.env_replaced.home)
  end)

  it("can set environment variables in the adapter", function()
    local adapter = require("codecompanion.adapters").extend(test_adapter2)
    adapter:get_env_vars()

    local url = adapter:set_env_vars(adapter.url)
    h.eq("https://api.oli.ai/v1/chat/oli_model_v2", url)

    local headers = adapter:set_env_vars(adapter.headers)
    h.eq({
      content_type = "application/json",
      home = os.getenv("HOME"),
    }, headers)
  end)

  it("will not set environment variables if it doesn't need to", function()
    local adapter = require("codecompanion.adapters").extend(test_adapter2)
    adapter:get_env_vars()

    local params = adapter:set_env_vars(adapter.parameters)
    h.eq(test_adapter2.parameters, params)
  end)

  it("can consolidate consecutive messages", function()
    local messages = {
      { role = "system", content = "This is a system prompt" },
      { role = "user", content = "Foo" },
      { role = "user", content = "Bar" },
    }

    h.eq({
      { role = "system", content = "This is a system prompt" },
      { role = "user", content = "Foo Bar" },
    }, utils.merge_messages(messages))
  end)

  it("can be used to remove groups of messages", function()
    local messages = {
      { role = "system", content = "This is a system prompt" },
      { role = "system", content = "This is another system prompt" },
      { role = "user", content = "Foo" },
      { role = "user", content = "Bar" },
    }

    -- Taken directly from the Anthropic adapter
    local sys_prompt = utils.get_msg_index("system", messages)
    if sys_prompt and #sys_prompt > 0 then
      -- Sort the prompts in descending order so we can remove them from the table without shifting indexes
      table.sort(sys_prompt, function(a, b)
        return a > b
      end)
      for _, prompt in ipairs(sys_prompt) do
        table.remove(messages, prompt)
      end
    end

    h.eq({
      { role = "user", content = "Foo" },
      { role = "user", content = "Bar" },
    }, messages)
  end)
end)
