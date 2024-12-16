local new_set = MiniTest.new_set
local h = require("tests.helpers")

local T = MiniTest.new_set()

local chat

T["References"] = new_set({
  hooks = {
    pre_once = function()
      chat, _ = h.setup_chat_buffer()
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["References"]["Can be added to the UI of the chat buffer"] = function()
  chat.References:add({
    source = "test",
    name = "test",
    id = "testing",
  })
  chat.References:add({
    source = "test",
    name = "test",
    id = "testing again",
  })

  chat:submit()

  local buffer = h.get_buf_lines(chat.bufnr)
  h.eq("> Sharing:", buffer[3])
  h.eq("> - testing", buffer[4])
  h.eq("> - testing again", buffer[5])
end

return T
