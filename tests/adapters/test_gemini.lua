local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Gemini adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("gemini")
    end,
  },
})

T["Gemini adapter"]["can form messages to be sent to the API"] = function()
  local messages = {
    {
      content = "Follow the user's request",
      role = "system",
    },
    {
      content = "Respond in code",
      role = "system",
    },
    {
      content = "Explain Ruby in two words",
      role = "user",
    },
  }

  local output = {
    system_instruction = {
      role = "user",
      parts = {
        { text = "Follow the user's request" },
        { text = "Respond in code" },
      },
    },
    contents = {
      {
        role = "user",
        parts = {
          { text = "Explain Ruby in two words" },
        },
      },
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages))
end

T["Gemini adapter"]["can form messages with system prompt"] = function()
  local messages_with_system = {
    {
      content = "You are a helpful assistant",
      role = "system",
      id = 1,
      cycle = 1,
      opts = { visible = false },
    },
    {
      content = "hello",
      id = 2,
      opts = { visible = true },
      role = "user",
    },
    {
      content = "Hi, how can I help?",
      id = 3,
      opts = { visible = true },
      role = "llm",
    },
  }

  local output = {
    system_instruction = {
      role = "user",
      parts = {
        { text = "You are a helpful assistant" },
      },
    },
    contents = {
      {
        role = "user",
        parts = {
          { text = "hello" },
        },
      },
      {
        role = "user",
        parts = {
          { text = "Hi, how can I help?" },
        },
      },
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages_with_system))
end

T["Gemini adapter"]["can form messages without system prompt"] = function()
  local messages_without_system = {
    {
      content = "hello",
      id = 1,
      opts = { visible = true },
      role = "user",
    },
    {
      content = "Hi, how can I help?",
      id = 2,
      opts = { visible = true },
      role = "llm",
    },
  }

  local output = {
    contents = {
      {
        role = "user",
        parts = {
          { text = "hello" },
        },
      },
      {
        role = "user",
        parts = {
          { text = "Hi, how can I help?" },
        },
      },
    },
  }

  h.eq(output, adapter.handlers.form_messages(adapter, messages_without_system))
end

T["Gemini adapter"]["Streaming"] = new_set()

T["Gemini adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/stubs/gemini_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end

  h.expect_starts_with("Interpreted, versatile.", output)
end

T["Gemini adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("gemini", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["Gemini adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/gemini_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Elegant, dynamic.", adapter.handlers.chat_output(adapter, json).output.content)
end

T["Gemini adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/adapters/stubs/gemini_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }

  h.expect_starts_with("Elegant, dynamic.", adapter.handlers.inline_output(adapter, json).output)
end

return T
