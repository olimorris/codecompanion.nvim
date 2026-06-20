local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["OpenRouter adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("openrouter")
    end,
  },
})

T["OpenRouter adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests.interactions.chat.tools.builtin.stubs.weather").schema
  local tools = { weather = { weather } }

  h.eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["OpenRouter adapter"]["forms reasoning output"] = function()
  local messages = {
    {
      content = "Considering ",
      reasoning_details = {
        { type = "reasoning.summary", summary = "Considering ", format = "openai-responses-v1", index = 0 },
      },
    },
    {
      content = "concise descriptions",
      reasoning_details = {
        { type = "reasoning.summary", summary = "concise descriptions", format = "openai-responses-v1", index = 0 },
      },
    },
    {
      reasoning_details = {
        { type = "reasoning.encrypted", data = "gAAAABc123", format = "openai-responses-v1" },
      },
    },
  }

  local form_reasoning = adapter.handlers.form_reasoning(adapter, messages)

  h.eq("Considering concise descriptions", form_reasoning.content)

  -- The summary deltas merge into one block; the encrypted block is kept separate
  h.eq({
    {
      type = "reasoning.summary",
      summary = "Considering concise descriptions",
      format = "openai-responses-v1",
      index = 0,
    },
    { type = "reasoning.encrypted", data = "gAAAABc123", format = "openai-responses-v1" },
  }, form_reasoning._data.reasoning_details)
end

T["OpenRouter adapter"]["sends preserved reasoning back to the API"] = function()
  local messages = {
    { role = "user", content = "Reason before you answer, but explain Ruby in two words" },
    {
      role = "assistant",
      content = "Elegant scripting",
      reasoning = {
        content = "The user wants Ruby in two words",
        _data = {
          reasoning_details = {
            {
              type = "reasoning.encrypted",
              format = "openai-responses-v1",
              index = 0,
              id = "rs_0c65cb03bb4a9d12016a36f0924af8819599444960751567c6",
              data = "gAAAAABqNvCTh5Tf",
            },
          },
        },
      },
    },
    { role = "user", content = "Okay, awesome. Thank you" },
  }

  local result = adapter.handlers.form_messages(adapter, messages)

  h.eq({
    { role = "user", content = "Reason before you answer, but explain Ruby in two words" },
    {
      role = "assistant",
      content = "Elegant scripting",
      reasoning_details = {
        {
          type = "reasoning.encrypted",
          format = "openai-responses-v1",
          index = 0,
          id = "rs_0c65cb03bb4a9d12016a36f0924af8819599444960751567c6",
          data = "gAAAAABqNvCTh5Tf",
        },
      },
    },
    { role = "user", content = "Okay, awesome. Thank you" },
  }, result.messages)
end

T["OpenRouter adapter"]["can output tool call"] = function()
  local output = "The weather in London is 15 degrees"
  local tool_call = {
    ["function"] = {
      arguments = '{"location": "London", "units": "celsius"}',
      name = "weather",
    },
    id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
    type = "function",
  }

  h.eq({
    content = output,
    opts = {
      visible = false,
    },
    role = "tool",
    tools = {
      call_id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
      name = "weather",
    },
  }, adapter.handlers.tools.output_response(adapter, tool_call, output))
end

T["OpenRouter adapter"]["Streaming"] = new_set()

T["OpenRouter adapter"]["Streaming"]["can process reasoning output"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openrouter_reasoning_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output and chat_output.output.reasoning and chat_output.output.reasoning.content then
      output = output .. chat_output.output.reasoning.content
    end
  end

  h.expect_starts_with("**Considering concise descriptions**", output)
end

T["OpenRouter adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/adapters/http/stubs/openrouter_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 0,
      ["function"] = {
        arguments = '{"filepath":"/Users/Oli/Code/Neovim/codecompanion.nvim/version.txt","end_line_number_base_zero":-1,"start_line_number_base_zero":0}',
        name = "read_file",
      },
      id = "call_yqZoquE7i7crGNV4S4uZo902",
      type = "function",
    },
  }

  h.eq(tool_output, tools)
end

T["OpenRouter adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend("openrouter", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

T["OpenRouter adapter"]["No Streaming"]["can process reasoning output"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openrouter_reasoning_no_streaming.txt")
  data = table.concat(data, "\n")

  -- Match the format of the actual request
  local json = { body = data }
  local reasoning = adapter.handlers.chat_output(adapter, json).output.reasoning

  h.eq("reasoning.encrypted", reasoning.reasoning_details[1].type)
  h.eq("rs_060760fe184081ec016a36d693b04c8195954f752e67fd2ac0", reasoning.reasoning_details[1].id)
  h.expect_starts_with("gAAAAABqNtaW", reasoning.reasoning_details[1].data)
end

T["OpenRouter adapter"]["No Streaming"]["can process tools"] = function()
  local data = vim.fn.readfile("tests/adapters/http/stubs/openrouter_tools_no_streaming.txt")
  data = table.concat(data, "\n")

  local tools = {}

  -- Match the format of the actual request
  local json = { body = data }
  adapter.handlers.chat_output(adapter, json, tools)

  local tool_output = {
    {
      _index = 1,
      ["function"] = {
        arguments = '{"end_line_number_base_zero":-1,"filepath":"/Users/Oli/Code/Neovim/codecompanion.nvim/version.txt","start_line_number_base_zero":0}',
        name = "read_file",
      },
      id = "call_BEYgGLlPOUOpUwkQkYMaq1k2",
      type = "function",
    },
  }
  h.eq(tool_output, tools)
end

return T
