local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, tools

T["Tools"] = new_set({
  hooks = {
    pre_once = function()
      chat, tools = h.setup_chat_buffer()
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Tools"][":parse"] = new_set()

T["Tools"][":parse"]["should parse a message with a tool"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "@foo do some stuff",
  })
  tools:parse(chat, chat.messages[#chat.messages])
  local messages = chat.messages

  h.eq("My tool system prompt", messages[#messages - 1].content)
  h.eq("foo", messages[#messages].content)
end

T["Tools"][":replace"] = new_set()

T["Tools"][":replace"]["should replace the tool in the message"] = function()
  local message = "@foo replace this tool"
  local result = tools:replace(message, "foo")
  h.eq("replace this tool", result)
end

return T
