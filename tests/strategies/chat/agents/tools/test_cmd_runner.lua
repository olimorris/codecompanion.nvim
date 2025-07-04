local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

        _G.output = nil
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["cmd_runner tool"] = function()
  child.lua([[
    require("tests.log")
    local tool = {
      {
        ["function"] = {
          name = "cmd_runner",
          arguments = '{"cmd": "echo hello world"}',
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  expect.reference_screenshot(child.get_screenshot())
end

return T
