local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

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
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "cmd",
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(100)
  ]])

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
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "cmd_error",
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(100)
  ]])

  -- output.error
  h.eq("Error", child.lua_get("_G._test_output"))

  -- Order of execution
  h.eq("Error->Exit", child.lua_get("_G._test_order"))
end

T["Agent"]["cmds"]["can run multiple commands"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "cmd_consecutive",
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(100)
  ]])

  -- on_exit should only be called at the end
  h.eq("Setup->Success->Success->Exit", child.lua_get("_G._test_order"))

  -- output.success should be called for each command
  h.eq({ { "Hello World" } }, child.lua_get("_G._test_output[1]"))
  h.eq({ { "Hello CodeCompanion" } }, child.lua_get("_G._test_output[2]"))
  h.eq(vim.NIL, child.lua_get("_G._test_output[3]"))
end

T["Agent"]["cmds"]["can set test flags on the chat object"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "mock_cmd_runner",
          arguments = '{"cmds": "ls", "flag": "testing"}',
        }
      },
    }
    agent:execute(chat, tool)
    vim.wait(100)
  ]])

  h.eq({ testing = true }, child.lua_get("agent.chat.tools.flags"))
end

return T
