local config = require("codecompanion.config")

local new_set = MiniTest.new_set
local h = require("tests.helpers")

local T = MiniTest.new_set()

local chat

T["Subscribers"] = new_set({
  hooks = {
    pre_case = function()
      chat, _ = h.setup_chat_buffer()
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Subscribers"]["Can subscribe to chat buffer"] = function()
  local message = "Adding Subscriber Message"

  chat.subscribers:subscribe({
    id = "testing",
    callback = function()
      chat:add_buf_message({ content = message })
    end,
  })
  chat:add_buf_message({ role = "user", content = "Hello World" })

  local buffer = h.get_buf_lines(chat.bufnr)
  h.eq({ "## foo", "", "Hello World" }, buffer)

  h.send_to_llm(chat, "Hello there")

  buffer = h.get_buf_lines(chat.bufnr)
  h.eq(message, buffer[#buffer])
end

return T
