local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Mistral adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("mistral")
    end,
  },
})

T["Mistral adapter"]["form_messages"] = new_set()

T["Mistral adapter"]["form_messages"]["it can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }

  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["Mistral adapter"]["form_messages"]["it can form messages with tools"] = function()
  local input = {
    { role = "system", content = "System Prompt 1" },
    { role = "user", content = "User1" },
    {
      role = "llm",
      tools = {
        calls = {
          {
            ["function"] = {
              arguments = '{"location":"London, UK","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_1_a460d461-60a7-468c-a699-ef9e2dced125",
            type = "function",
          },
          {
            ["function"] = {
              arguments = '{"location":"Paris, France","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_0_bb2a2194-a723-44a6-a1f8-bd05e9829eea",
            type = "function",
          },
        },
      },
    },
  }

  local expected = {
    messages = {
      {
        content = "System Prompt 1",
        role = "system",
      },
      {
        content = "User1",
        role = "user",
      },
      {
        role = "llm",
        tool_calls = {
          {
            ["function"] = {
              arguments = '{"location":"London, UK","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_1_a460d461-60a7-468c-a699-ef9e2dced125",
            type = "function",
          },
          {
            ["function"] = {
              arguments = '{"location":"Paris, France","units":"fahrenheit"}',
              name = "weather",
            },
            id = "call_0_bb2a2194-a723-44a6-a1f8-bd05e9829eea",
            type = "function",
          },
        },
      },
    },
  }

  h.eq(expected, adapter.handlers.form_messages(adapter, input))
end

T["Mistral adapter"]["form_messages"]["it can form tools to be sent to the API"] = function()
  adapter = require("codecompanion.adapters").extend("mistral", {
    schema = {
      model = {
        default = "mistral-chat",
      },
    },
  })

  local weather = require("tests.strategies.chat.tools.catalog.stubs.weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["Mistral adapter"]["Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("mistral", {
        opts = {
          stream = true,
        },
      })
    end,
  },
})
T["Mistral adapter"]["Streaming"]["can output streamed data into a format for the chat buffer"] = function()
  local lines = vim.fn.readfile("tests/adapters/http/stubs/mistral_streaming.txt")
  local output = ""
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end
  h.eq("Dynamic Language", output)
end

T["Mistral adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/http/stubs/mistral_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      ["function"] = {
        arguments = '{"location": "Paris, France", "units": "celsius"}',
        name = "weather",
      },
      id = "3sKXImamX",
    },
    {
      ["function"] = {
        arguments = '{"location": "London, United Kingdom", "units": "celsius"}',
        name = "weather",
      },
      id = "22sZzWH6p",
    },
  }

  h.eq(tool_output, tools)
end

T["Mistral adapter"]["Streaming"]["can process thinking"] = function()
  local lines = vim.fn.readfile("tests/adapters/http/stubs/mistral_thinking_streaming.txt")
  local output = {}
  for _, line in ipairs(lines) do
    table.insert(output, adapter.handlers.chat_output(adapter, line, {}))
  end

  h.eq(output, {
    {
      status = "success",
      output = { reasoning = { content = "Okay" } },
    },
    {
      status = "success",
      output = { reasoning = { content = ", that works" } },
    },
  })
end

-- No streaming ---------------------------------------------------------------

T["Mistral adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("mistral", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Mistral adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/mistral_no_streaming.txt")
  data = table.concat(data, "\n")

  h.eq("Dynamic Language", adapter.handlers.chat_output(adapter, data).output.content)
end

T["Mistral adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/mistral_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      ["function"] = {
        arguments = '{"units": "celsius", "location": "London, UK"}',
        name = "weather",
      },
      id = "ARMRcKTps",
    },
    {
      ["function"] = {
        arguments = '{"units": "celsius", "location": "Paris, France"}',
        name = "weather",
      },
      id = "6HQYyBgbW",
    },
  }

  h.eq(tool_output, tools)
end

T["Mistral adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/mistral_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq("Dynamic Language", adapter.handlers.inline_output(adapter, json).output)
end

return T
