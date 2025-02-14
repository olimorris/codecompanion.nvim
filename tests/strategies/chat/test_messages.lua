local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local chat

T["Messages"] = new_set({
  hooks = {
    pre_case = function()
      chat, _ = h.setup_chat_buffer()
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Messages"]["Can be parsed in the chat buffer"] = function()
  chat:add_buf_message({ role = "user", content = "Hello World" })

  local buffer = h.get_buf_lines(chat.bufnr)
  h.eq({ "## foo", "", "Hello World" }, buffer)

  h.send_to_llm(chat, "Hello there")
  buffer = h.get_buf_lines(chat.bufnr)

  h.eq("Hello there", buffer[#buffer - 4])
  h.eq("## foo", buffer[#buffer - 2])
  h.eq("", buffer[#buffer])
end

return T
