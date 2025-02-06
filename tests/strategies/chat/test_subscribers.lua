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
    data = { type = "once" },
    callback = function()
      chat:add_buf_message({ content = message })
    end,
  })

  h.eq(#chat.subscribers.queue, 1)
  chat:add_buf_message({ role = "user", content = "Hello World" })

  local buffer = h.get_buf_lines(chat.bufnr)
  h.eq({ "## foo", "", "Hello World" }, buffer)

  h.send_to_llm(chat, "Hello there")
  buffer = h.get_buf_lines(chat.bufnr)

  -- Confirm subscriber message has been added to the chat buffer
  h.eq(message, buffer[#buffer])
  -- and removed from the subscriber queue
  h.eq(#chat.subscribers.queue, 0)

  h.send_to_llm(chat, "Hello again")
  buffer = h.get_buf_lines(chat.bufnr)

  -- and not re-added to the chat buffer
  h.eq("Hello again", buffer[#buffer - 4])
end

return T
