local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      -- Load helpers and set up environment in child process
      child.lua([[
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

        -- Reset test globals
        vim.g.codecompanion_test_setup = nil
        vim.g.codecompanion_test_exit = nil
        vim.g.codecompanion_test_output = nil

        -- Set up mocks
        h.mock_job()

        -- Mock vim.schedule
        vim.schedule = function(cb)
          cb()
        end
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Agent"] = new_set()
T["Agent"]["cmds"] = new_set()

T["Agent"]["cmds"]["setup and on_exit handlers are called once"] = function()
  local tool = "'cmd'"
  child.lua(string.format(
    [[
    local cmd_xml = require("tests.strategies.chat.agents.tools.stubs.cmd_xml")
    local xml = cmd_xml.tool(%s)
    agent:execute(chat, xml)
    vim.wait(10)
  ]],
    tool
  ))

  local setup = child.lua_get("vim.g.codecompanion_test_setup")
  local exit = child.lua_get("vim.g.codecompanion_test_exit")

  h.eq(setup, "Setup")
  h.eq(exit, "Exited")
end

-- T["Agent"]["cmds"]["output.success is called"] = function()
--   agent:execute(
--     chat,
--     [[<tools>
--   <tool name="cmd"></tool>
-- </tools>]]
--   )
--   h.eq("Ran with success", vim.g.codecompanion_test_output)
-- end

return T
