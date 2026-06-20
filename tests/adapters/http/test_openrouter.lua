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
      adapter = require("codecompanion.adapters").extend("openai", {
        opts = {
          stream = false,
        },
      })
    end,
  },
})

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
