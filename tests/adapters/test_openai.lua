local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["OpenAI adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("openai")
    end,
  },
})

T["OpenAI adapter"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["OpenAI adapter"]["it can form tools to be sent to the API"] = function()
  local tools = {
    {
      weather = {
        ["function"] = {
          description = "Retrieves current weather for the given location.",
          name = "get_weather",
          parameters = {
            additionalProperties = false,
            properties = {
              location = {
                description = "City and country e.g. Bogotá, Colombia",
                type = "string",
              },
              units = {
                description = "Units the temperature will be returned in.",
                enum = { "celsius", "fahrenheit" },
                type = "string",
              },
            },
            required = { "location", "units" },
            type = "object",
          },
          strict = true,
        },
        type = "function",
      },
    },
  }

  h.eq({
    tools = {
      {
        ["function"] = {
          description = "Retrieves current weather for the given location.",
          name = "get_weather",
          parameters = {
            additionalProperties = false,
            properties = {
              location = {
                description = "City and country e.g. Bogotá, Colombia",
                type = "string",
              },
              units = {
                description = "Units the temperature will be returned in.",
                enum = { "celsius", "fahrenheit" },
                type = "string",
              },
            },
            required = { "location", "units" },
            type = "object",
          },
          strict = true,
        },
        type = "function",
      },
    },
  }, adapter.handlers.form_tools(adapter, tools))
end

T["OpenAI adapter"]["Streaming"] = new_set()

T["OpenAI adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/stubs/openai_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Dynamic, Flexible", output)
end

T["OpenAI adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("openai", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["OpenAI adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/openai_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Elegant simplicity.", adapter.handlers.chat_output(adapter, json).output.content)
end

T["OpenAI adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/openai_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Elegant simplicity.", adapter.handlers.inline_output(adapter, json).output)
end

return T
