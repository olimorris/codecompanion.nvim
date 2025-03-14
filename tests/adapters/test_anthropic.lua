local h = require("tests.helpers")
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

T["Anthropic adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/anthropic_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Dynamic elegance", adapter.handlers.inline_output(adapter, json).output)
end

return T
