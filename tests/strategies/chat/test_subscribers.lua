local h = require("tests.helpers")

local new_set = MiniTest.new_set
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

  h.eq(chat.subscribers:size(), 1)
  chat:add_buf_message({ role = "user", content = "Hello World" })

  local buffer = h.get_buf_lines(chat.bufnr)
  h.eq({ "## foo", "", "Hello World" }, buffer)

  h.send_to_llm(chat, "Hello there")
  buffer = h.get_buf_lines(chat.bufnr)

  -- Confirm subscriber message has been added to the chat buffer
  h.eq(message, buffer[#buffer])
  -- and removed from the subscriber queue
  h.eq(chat.subscribers:size(), 0)

  h.send_to_llm(chat, "Hello again")
  buffer = h.get_buf_lines(chat.bufnr)

  -- and not re-added to the chat buffer
  h.eq("Hello again", buffer[#buffer - 4])
end

T["Subscribers"]["size() reflects queue size"] = function()
  local ev1 = { data = { type = "once" }, callback = function() end }
  local ev2 = { data = { type = "once" }, callback = function() end }

  chat.subscribers:subscribe(ev1)
  chat.subscribers:subscribe(ev2)

  h.eq(chat.subscribers:size(), 2)

  chat.subscribers:unsubscribe(ev1)
  h.eq(chat.subscribers:size(), 1)

  -- Processing should consume the remaining once event
  h.send_to_llm(chat, "trigger processing")
  h.eq(chat.subscribers:size(), 0)
end

T["Subscribers"]["on_stop marks subscribers as stopped"] = function()
  local ev = { data = { type = "once", opts = { auto_submit = true } }, callback = function() end }
  chat.subscribers:subscribe(ev)

  h.eq(chat.subscribers:size(), 1)
  h.is_false(chat.subscribers.stopped)

  -- Lifecycle stop event (wired to subscribers:stop() via on_stop)
  chat:dispatch("on_stop")
  h.is_true(chat.subscribers.stopped)
end

return T
