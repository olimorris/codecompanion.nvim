local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _G.tools = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.chat = nil
        _G.tools = nil
        _G.tool = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["Tool output"] = new_set()

---The tool call that's used in the tests
---@param c MiniTest.child
---@return nil
function tool_call(c)
  c.lua([[
    _G.tool = {
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
  ]])
end

T["Tool output"]["first call creates one message"] = function()
  tool_call(child)
  local output = child.lua([[
    local chat = _G.chat

    chat:add_tool_output(_G.tool, { content = "Hello!" })

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
  tool_call(child)
  local output = child.lua([[
    local chat = _G.chat

    -- first insert
    chat:add_tool_output(_G.tool, { content = "Hello!" })
    -- second insert with same id => should append
    chat:add_tool_output(_G.tool, { content = "Again!" })

    return {
      count = #chat.messages,
      content = chat.messages[#chat.messages].content,
    }
  ]])

  h.eq(output.count, 2)
  h.eq(output.content, "Hello!\n\nAgain!")
end

return T
