local h = require("tests.helpers")
local transform = require("codecompanion.utils.tool_transformers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Anthropic adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("anthropic")
    end,
  },
})

T["Anthropic adapter"]["consolidates system prompts in their own block"] = function()
  local messages = {
    { content = "Hello", role = "system" },
    { content = "World", role = "system" },
    { content = "What can you do?!", role = "user" },
  }

  local output = adapter.handlers.form_messages(adapter, messages)

  h.eq("Hello", output.system[1].text)
  h.eq("World", output.system[2].text)
  h.eq({ { content = "What can you do?!", role = "user" } }, output.messages)
end

T["Anthropic adapter"]["can form messages to be sent to the API"] = function()
  local messages = { {
    content = "Explain Ruby in two words",
    role = "user",
  } }
  h.eq({ messages = messages }, adapter.handlers.form_messages(adapter, messages))
end

T["Anthropic adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests/strategies/chat/agents/tools/stubs/weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { transform.to_anthropic(weather) } }, adapter.handlers.form_tools(adapter, tools))
end

T["Anthropic adapter"]["consolidates consecutive user messages together"] = function()
  local messages = {
    { content = "Hello", role = "user" },
    { content = "World!", role = "user" },
    { content = "What up?!", role = "user" },
  }

  h.eq(
    { { role = "user", content = "Hello\n\nWorld!\n\nWhat up?!" } },
    adapter.handlers.form_messages(adapter, messages).messages
  )
end

T["Anthropic adapter"]["Non-Reasoning models have less tokens"] = function()
  local non_reasoning = require("codecompanion.adapters").extend("anthropic", {
    schema = {
      model = {
        default = "claude-3-5-sonnet-20241022",
      },
    },
  })
  local output = require("codecompanion.adapters").resolve(non_reasoning)
  h.eq(4096, output.schema.max_tokens.default(non_reasoning))
end

T["Anthropic adapter"]["Reasoning models have more tokens"] = function()
  local reasoning = require("codecompanion.adapters").extend("anthropic", {
    schema = {
      model = {
        default = "claude-3-7-sonnet-20250219",
      },
    },
  })
  local output = require("codecompanion.adapters").resolve(reasoning)
  h.eq(17000, output.schema.max_tokens.default(reasoning))
end

T["Anthropic adapter"]["Streaming"] = new_set()

T["Anthropic adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/stubs/anthropic_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Dynamic elegance", output)
end

T["Anthropic adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/stubs/anthropic_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    ["1"] = {
      arguments = '{"location": "London, UK", "units": "celsius"}',
      name = "weather",
    },
    ["2"] = {
      arguments = '{"location": "Paris, France", "units": "celsius"}',
      name = "weather",
    },
  }

  h.eq(tool_output, tools)
end

T["Anthropic adapter"]["Streaming"]["can process reasoning output"] = function()
  local output = {
    content = "",
    reasoning = "",
  }
  local lines = vim.fn.readfile("tests/adapters/stubs/anthropic_reasoning_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output then
      if chat_output.output.reasoning then
        output.reasoning = output.reasoning .. chat_output.output.reasoning
      end
      if chat_output.output.content then
        output.content = output.content .. chat_output.output.content
      end
    end
  end

  h.expect_starts_with("**Elegant simplicity**", output.content)
  h.expect_starts_with("The user is asking me to describe the Ruby programming language", output.reasoning)
end

T["Anthropic adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("anthropic", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Anthropic adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Dynamic elegance", adapter.handlers.chat_output(adapter, json).output.content)
end

T["Anthropic adapter"]["No Streaming"]["can output for the inline assistant with non reasoning models"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Dynamic elegance", adapter.handlers.inline_output(adapter, json).output)
end

T["Anthropic adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    toolu_01TSJjnB81vBBT8dhP3tTCaM = {
      arguments = {
        location = "London, UK",
        units = "celsius",
      },
      name = "weather",
    },
    toolu_01UEd4jZFvj5gdqyL1L7QTqg = {
      arguments = {
        location = "Paris, France",
        units = "celsius",
      },
      name = "weather",
    },
  }
  h.eq(tool_output, tools)
end

T["Anthropic adapter"]["No Streaming"]["can output for the inline assistant with reasoning models"] = function()
  adapter = require("codecompanion.adapters").extend("anthropic", {
    opts = {
      stream = false,
      can_reason = true,
    },
  })

  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_reasoning_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.eq(
    [[<response>\n  <code>hello world</code>\n  <language>lua</language>\n  <placement>add</placement>\n</response>]],
    adapter.handlers.inline_output(adapter, json).output
  )
end

return T
