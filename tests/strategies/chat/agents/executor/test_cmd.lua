local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      -- Load helpers and set up the environment in the child process
      child.lua([[
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

        -- Reset test globals
        _G._test_setup = nil
        _G._test_exit = nil
        _G._test_order = nil
        _G._test_output = nil
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

T["Agent"]["cmds"]["handlers and outputs are called"] = function()
  local tool = "'cmd'"
  child.lua(string.format(
    [[
    local cmd_xml = require("tests.strategies.chat.agents.tools.stubs.xml.cmd_xml")
    local xml = cmd_xml.load(%s)
    agent:execute(chat, xml)
    vim.wait(100)
  ]],
    tool
  ))

  -- handlers.setup
  h.eq("Setup", child.lua_get("_G._test_setup"))
  -- output.success
  h.eq("Hello World", child.lua_get("_G._test_output[1][1][1]"))
  -- handlers.on_exit
  h.eq("Exited", child.lua_get("_G._test_exit"))

  -- Order of execution
  h.eq("Setup->Success->Exit", child.lua_get("_G._test_order"))
end

T["Agent"]["cmds"]["output.errors is called"] = function()
  local tool = "'cmd_error'"
  child.lua(string.format(
    [[
    local cmd_xml = require("tests.strategies.chat.agents.tools.stubs.xml.cmd_xml")
    local xml = cmd_xml.load(%s)
    agent:execute(chat, xml)
    vim.wait(100)
  ]],
    tool
  ))

  -- output.error
  h.eq("Error", child.lua_get("_G._test_output"))

  -- Order of execution
  h.eq("Error->Exit", child.lua_get("_G._test_order"))
end

-- Test that flags get inserted into a chat buffer
T["Agent"]["cmds"]["can set test flags"] = function()
  child.lua([[
    local cmd_xml = require("tests.strategies.chat.agents.tools.stubs.xml.cmd_xml")
    local xml = cmd_xml.test_flag()
    agent:execute(chat, xml)
    vim.wait(100)
  ]])

  h.eq({ testing = true }, child.lua_get("agent.chat.tool_flags"))
end

-- Test multiple commands

return T
