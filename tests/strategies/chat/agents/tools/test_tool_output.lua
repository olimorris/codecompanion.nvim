local h = require("tests.helpers")

local tools = {
  tool1 = {
    name = "weather",
    function_call = {
      _index = 0,
      ["function"] = {
        arguments = '{"location": "London", "units": "celsius"}',
        name = "weather",
      },
      id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
      type = "function",
    },
  },
  tool2 = {
    name = "weather",
    function_call = {
      _index = 1,
      ["function"] = {
        arguments = '{"location": "Paris", "units": "celsius"}',
        name = "weather",
      },
      id = "call_a9oyUMlFhnX8HvqzlfIx5Uek",
      type = "function",
    },
  },
}

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _G.agent = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["Tool output"] = new_set()

T["Tool output"]["first call creates one message"] = function()
  local output = child.lua([[
    local chat = _G.chat

    local tool = {
      name = "weather",
      function_call = {
        _index = 0,
        ["function"] = {
          arguments = '{"location": "London", "units": "celsius"}',
          name = "weather",
        },
        id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
        type = "function",
      },
    }
    chat:add_tool_output(tool, "Hello!")

    -- return how many chat.messages and that message's content
    return {
      count = #chat.messages,
      content = chat.messages[#chat.messages].content,
    }
  ]])

  h.eq(output.count, 2)
  h.eq(output.content, "Hello!")
end

T["Tool output"]["second call appends to same message"] = function()
  local output = child.lua([[
    local chat = _G.chat

    local tool = {
      name = "weather",
      function_call = {
        ["function"] = {
          arguments = '{"location": "London", "units": "celsius"}',
          name = "weather",
        },
        id = "call_RJU6xfk0OzQF3Gg9cOFS5RY7",
        type = "function",
      },
    }

    -- first insert
    chat:add_tool_output(tool, "Hello!")
    -- second insert with same id => should append
    chat:add_tool_output(tool, "Again!")

    return {
      count = #chat.messages,
      content = chat.messages[#chat.messages].content,
    }
  ]])

  h.eq(output.count, 2)
  h.eq(output.content, "Hello!\n\nAgain!")
end

return T
