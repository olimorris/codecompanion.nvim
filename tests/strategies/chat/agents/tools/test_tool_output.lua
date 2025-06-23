local h = require("tests.helpers")

local expect = MiniTest.expect
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

local chat_buffer_output = function(c)
  c.lua([[
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

    h.make_tool_call(chat, tool, "**Weather Tool**: Ran successfully:\nTemperature: 20°C\nCondition: Sunny\nPrecipitation: 0%", {
      llm_initial_response = "I've found some awesome weather data for you:",
      llm_final_response = "Let me know if you need anything else!",
    })
  ]])
end

T["Tool output"]["is displayed and formatted in the chat buffer"] = function()
  chat_buffer_output(child)
  expect.reference_screenshot(child.get_screenshot())
end

T["Tool output"]["can be folded in the chat buffer"] = function()
  child.lua([[
    _G.chat, _G.agent = h.setup_chat_buffer({
      strategies = {
        chat = {
          tools = {
            opts = {
              folds = {
                enabled = true,
              }
            }
          }
        }
      }
    })
  ]])

  chat_buffer_output(child)
  expect.reference_screenshot(child.get_screenshot())
end

T["Tool output"]["does not fold single line output but applies extmarks"] = function()
  child.lua([[
     _G.chat, _G.agent = h.setup_chat_buffer({
       strategies = {
         chat = {
           tools = {
             opts = {
               folds = {
                 enabled = true,
               }
             }
           }
         }
       }
     })
   ]])

  child.lua([[
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

    h.make_tool_call(chat, tool, "**Weather Tool**: Ran successfully", {
      llm_initial_response = "I've found some awesome weather data for you:",
    })
   ]])

  expect.reference_screenshot(child.get_screenshot())
end

return T
