local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, vars

T["Variables"] = new_set({
  hooks = {
    pre_once = function()
      chat, _, vars = h.setup_chat_buffer()
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Variables"][":parse"] = new_set()
T["Variables"][":replace"] = new_set()

T["Variables"][":parse"]["should parse a message with a tool"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#foo what does this do?",
  })
  local result = vars:parse(chat, chat.messages[#chat.messages])

  h.eq(true, result)

  local message = chat.messages[#chat.messages]
  h.eq("foo", message.content)
end

T["Variables"][":parse"]["should return nil if no variable is found"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "what does this do?",
  })
  local result = vars:parse(chat, chat.messages[#chat.messages])

  h.eq(false, result)
end

T["Variables"][":parse"]["should parse a message with a variable and string params"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#bar:baz Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("bar baz", message.content)
end

T["Variables"][":parse"]["should parse a message with a variable and numerical params"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#bar:100-200 Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("bar 100-200", message.content)
end

T["Variables"][":parse"]["should parse a message with a variable and ignore params if they're not enabled"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#baz:qux Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("baz", message.content)
end

T["Variables"][":replace"]["should replace the variable in the message"] = function()
  local message = "#foo #bar replace this var"
  local result = vars:replace(message, "foo")
  h.eq("replace this var", result)
end

return T
