local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require('codecompanion.config')
        h.setup_plugin()
	builtin = require("codecompanion.interactions.background.builtin.chat_make_title")
      ]])
    end,
    post_once = child.stop,
  },
})

T["chat_make_title"] = new_set()

T["chat_make_title"]["can format messages"] = function()
  local messages = child.lua([[
    return builtin.format_messages({
      { role = "user", content = "Hello, how are you?" },
      { role = "assistant", content = "I am fine, thank you!" },
    })
  ]])

  h.eq(messages, "## user\nHello, how are you?\n## assistant\nI am fine, thank you!")
end

T["chat_make_title"]["formats a title on_done"] = function()
  local title = child.lua([[
    return builtin.on_done({
      output = {
	content = "Python Agent Chatbot"
      }
    })
  ]])

  h.eq(title, "Python Agent Chatbot")
end

return T
