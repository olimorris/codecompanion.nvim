local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.h = require('tests.helpers')
        _G.chat, _ = h.setup_chat_buffer({
          display = {
            chat = {
              show_settings = true,
            },
          },
        })
        ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Settings"] = new_set()

T["Settings"]["Are rendered correctly"] = function()
  expect.reference_screenshot(child.get_screenshot())
end

return T
