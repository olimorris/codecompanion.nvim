local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      -- Load helpers and set up the environment in the child process
      child.lua([[
        --require("tests.log")
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

        -- Reset test globals
        _G._test_func = nil
        _G._test_exit = nil
        _G._test_order = nil
        _G._test_output = nil
        _G._test_setup = nil
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Agent"] = new_set()
T["Agent"]["queue"] = new_set()

T["Agent"]["queue"]["can queue functions and commands"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_order]]))

  child.lua([[
    local queue = require("tests.strategies.chat.agents.tools.stubs.xml.queue_xml")
    local xml = queue.run()
    agent:execute(chat, xml)
    vim.wait(1000)
  ]])

  -- Test order
  h.eq(
    "Func[Setup]->Func[Success]->Func[Exit]->Cmd[Setup]->Cmd[Success]->Cmd[Exit]->Func2[Setup]->Func2[Success]->Func2[Exit]",
    child.lua_get([[_G._test_order]])
  )

  -- Test that the function was called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

return T
