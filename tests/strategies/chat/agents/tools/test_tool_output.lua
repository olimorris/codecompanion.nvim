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
        _G.chat = nil
        _G.agent = nil
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

---The tool call that's used in the tests
---@param c MiniTest.child
---@param message string The message to add to the chat buffer
---@return nil
local function set_buffer_contents(c, message)
  c.lua(string.format(
    [[
    local user_message = "%s"

    _G.chat:add_message({
      role = "user",
      content = user_message,
    })
    _G.chat:add_buf_message({
      role = "user",
      content = user_message,
    })

  ]],
    message
  ))
end

---Enabling folding in the chat buffer for tool output.
---@param c MiniTest.child
---@return nil
local function enable_folds(c)
  c.lua([[
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
end

T["Tool output"]["first call creates one message"] = function()
  tool_call(child)
  local output = child.lua([[
    local chat = _G.chat

    chat:add_tool_output(_G.tool, "Hello!")

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
    chat:add_tool_output(_G.tool, "Hello!")
    -- second insert with same id => should append
    chat:add_tool_output(_G.tool, "Again!")

    return {
      count = #chat.messages,
      content = chat.messages[#chat.messages].content,
    }
  ]])

  h.eq(output.count, 2)
  h.eq(output.content, "Hello!\n\nAgain!")
end

T["Tool output"]["is displayed and formatted in the chat buffer"] = function()
  set_buffer_contents(child, "Can you tell me the weather in London?")
  tool_call(child)
  child.lua([[
    h.make_tool_call(_G.chat, _G.tool, "**Weather Tool**: Ran successfully:\nTemperature: 20°C\nCondition: Sunny\nPrecipitation: 0%", {
      llm_initial_response = "I've found some awesome weather data for you:",
      llm_final_response = "Let me know if you need anything else!",
    })
  ]])

  expect.reference_screenshot(child.get_screenshot())
end

T["Tool output"]["Folds"] = new_set()

T["Tool output"]["Folds"]["can be folded"] = function()
  enable_folds(child)
  set_buffer_contents(child, "Can you tell me the weather in London?")
  tool_call(child)
  child.lua([[
    --require("tests.log")
    h.make_tool_call(_G.chat, _G.tool, "**Weather Tool**: Ran successfully:\nTemperature: 20°C\nCondition: Sunny\nPrecipitation: 0%", {
      llm_initial_response = "I've found some awesome weather data for you:",
      llm_final_response = "\nLet me know if you need anything else!",
    })
  ]])

  expect.reference_screenshot(child.get_screenshot())
end

T["Tool output"]["Folds"]["does not fold single line output but applies extmarks"] = function()
  enable_folds(child)
  set_buffer_contents(child, "Can you tell me the weather in London?")
  tool_call(child)
  child.lua([[
    --require("tests.log")
     h.make_tool_call(_G.chat, _G.tool, "**Weather Tool**: Ran successfully", {
       llm_initial_response = "I've found some awesome weather data for you:",
     })
   ]])

  expect.reference_screenshot(child.get_screenshot())
end

return T
