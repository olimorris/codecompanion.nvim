local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
      ]])
    end,
    post_once = function()
      child.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
  },
})

T["Slash Command Keymaps"] = new_set()

T["Slash Command Keymaps"]["can be obtained from the config"] = function()
  local result = child.lua([[
    local h = require("codecompanion.strategies.chat.helpers")
    return h.slash_command_keymaps(require("tests.config").strategies.chat.slash_commands)
  ]])

  h.eq({
    buffer = {
      callback = "keymaps.buffer",
      description = "Insert open buffers",
      modes = {
        i = "<C-b>",
        n = { "<C-b>", "gb" },
      },
    },
  }, result)
end

return T
