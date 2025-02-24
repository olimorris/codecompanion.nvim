local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      -- Load helpers and set up the environment in the child process
      child.lua([[
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
T["Agent"]["functions"] = new_set()

T["Agent"]["functions"]["can run"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points()
    agent:execute(chat, xml)
  ]])

  -- Test that the function was called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["calls output.success"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_output]]))

  child.lua([[
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points()
    agent:execute(chat, xml)
  ]])

  -- Test that the function was called
  h.eq("Ran with successRan with success", child.lua_get([[_G._test_output]]))
end

T["Agent"]["functions"]["calls on_exit only once"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_exit]]))

  child.lua([[
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points()
    agent:execute(chat, xml)
  ]])

  -- Test that the function was called
  h.eq("Exited", child.lua_get([[_G._test_exit]]))
end

T["Agent"]["functions"]["can run consecutively and pass input"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  local tool = "'func_consecutive'"
  child.lua(string.format(
    [[
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.one_data_point(%s)
    agent:execute(chat, xml)
  ]],
    tool
  ))

  -- Test that the function was called
  h.eq("Data 1 Data 1", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["can run consecutively"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  local tool = "'func_consecutive'"
  child.lua(string.format(
    [[
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points(%s)
    agent:execute(chat, xml)
  ]],
    tool
  ))

  -- Test that the function was called, overwriting the global variable
  h.eq("Data 1 Data 2 Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["can handle errors"] = function()
  local tool = "'func_error'"
  child.lua(string.format(
    [[
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points(%s)
    agent:execute(chat, xml)
  ]],
    tool
  ))

  -- Test that the `output.error` handler was called
  h.eq("<error>Something went wrong</error>", child.lua_get([[_G._test_output]]))
end

T["Agent"]["functions"]["can populate stderr and halt execution"] = function()
  local tool = "'func_error'"
  child.lua(string.format(
    [[
    -- Prevent stderr from being cleared out
    function agent:reset()
      return nil
    end
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points(%s)
    agent:execute(chat, xml)
  ]],
    tool
  ))

  -- Test that stderr is updated on the agent, only once
  h.eq({ "Something went wrong" }, child.lua_get([[agent.stderr]]))
end

T["Agent"]["functions"]["can populate stdout"] = function()
  child.lua([[
    -- Prevent stdout from being cleared out
    function agent:reset()
      return nil
    end
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points()
    agent:execute(chat, xml)
  ]])

  h.eq(
    { { data = "Data 1", status = "success" }, { data = "Data 2", status = "success" } },
    child.lua_get([[agent.stdout]])
  )
end

T["Agent"]["functions"]["calls handlers.setup once"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_setup]]))

  child.lua([[
    local func_xml = require("tests.strategies.chat.agents.tools.stubs.xml.func_xml")
    local xml = func_xml.two_data_points()
    agent:execute(chat, xml)
  ]])

  h.eq("Setup", child.lua_get([[_G._test_setup]]))
end

return T
