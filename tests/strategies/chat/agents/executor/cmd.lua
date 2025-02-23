local h = require("tests.helpers")
local log = require("codecompanion.utils.log")

local new_set = MiniTest.new_set
local T = new_set()

local chat, agent

T["Agent"] = new_set({
  hooks = {
    pre_case = function()
      chat, agent = h.setup_chat_buffer()
      -- Reset test globals
      vim.g.codecompanion_test_setup = nil
      vim.g.codecompanion_test_exit = nil
      vim.g.codecompanion_test_output = nil
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Agent"]["cmds"] = new_set()

T["Agent"]["cmds"]["can run"] = function()
  log:debug("=== TEST: Can run cmds ===")
  agent:execute(
    chat,
    [[<tools>
  <tool name="cmd"></tool>
</tools>]]
  )
  vim.cmd("redraw!")
  log:debug("=== TEST END ===")

  -- Test that the cmd ran
  h.eq(vim.g.codecompanion_test_setup, "Setup")
  h.eq(vim.g.codecompanion_test_exit, "Exited")
  h.eq(vim.g.codecompanion_test_output, "Ran with success")
end

return T
