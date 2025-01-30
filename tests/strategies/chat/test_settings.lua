local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, _

T["Settings"] = new_set({
  hooks = {
    pre_case = function()
      chat, _ = h.setup_chat_buffer({
        display = {
          chat = {
            show_settings = true,
          },
        },
      })
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Settings"]["Are rendered correctly"] = function()
  local buffer = h.get_buf_lines(chat.bufnr)

  h.eq("---", buffer[1])
  h.eq("model: gpt-3.5-turbo", buffer[2])
  h.eq("---", buffer[3])
end

return T
