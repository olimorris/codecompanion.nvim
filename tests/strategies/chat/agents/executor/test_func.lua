local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

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
    local tools = {
      {
        ["function"] = {
          name = "func",
          arguments = { data = "Data 1" },
        },
      },
    }
    agent:execute(chat, tools)
  ]])

  -- Test order
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the function was called
  h.eq("Data 1", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["can run functions of the same name consecutively"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    --require("tests.log")
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func",
        },
      },
       {
        ["function"] = {
          arguments = { data = "Data 2" },
          name = "func",
        },
      },
    }
    agent:execute(chat, tools)
  ]])

  -- Test order
  h.eq("Setup->Success->ExitSetup->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the function was called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["can run functions of the same name consecutively and not reuse handlers"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    --require("tests.log")
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_handlers_once",
        },
      },
      {
        ["function"] = {
          arguments = { data = "Data 2" },
          name = "func_handlers_once",
        },
      },
    }
    agent:execute(chat, tools)
  ]])

  -- Test order
  h.eq("Setup->Success->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the function was called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["can run functions of a different name consecutively"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func",
        },
      },
      {
        ["function"] = {
          arguments = { data = "Data 2" },
          name = "func2",
        },
      },
    }
    agent:execute(chat, tools)
  ]])

  -- Test order
  h.eq("Setup->Success->Exit->Setup->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the tools were called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["calls output.success"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_output]]))

  child.lua([[
    local tools = {
      {
        ["function"] = {
          name = "func",
          arguments = { data = "Data 1" },
        },
      },
    }
    agent:execute(chat, tools)
  ]])

  -- Test that the function was called
  h.eq("Ran with success", child.lua_get([[_G._test_output]]))
end

T["Agent"]["functions"]["can pass input to the next function"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_consecutive",
        },
      },
    }
    agent:execute(chat, tools)
   ]])

  h.eq("Setup->Success->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the functions was called
  h.eq("Data 1 Data 1", child.lua_get([[_G._test_func]]))
end

T["Agent"]["functions"]["can handle errors"] = function()
  child.lua([[
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_error",
        },
      },
    }
    agent:execute(chat, tools)
  ]])

  h.eq("Setup->Error->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the `output.error` handler was called
  h.eq("<error>Something went wrong</error>", child.lua_get([[_G._test_output]]))
end

T["Agent"]["functions"]["can return errors"] = function()
  child.lua([[
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_return_error",
        },
      },
    }
    agent:execute(chat, tools)
   ]])

  h.eq("Setup->Success->Error->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the `output.error` handler was called
  h.eq("<error>This will throw an error</error>", child.lua_get([[_G._test_output]]))
end

T["Agent"]["functions"]["can populate stderr and halt execution"] = function()
  child.lua([[
     -- Prevent stderr from being cleared out
     function agent:reset()
       return nil
     end
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_error",
        },
      },
    }
    agent:execute(chat, tools)
   ]])

  -- Test that stderr is updated on the agent, only once
  h.eq({ "Something went wrong" }, child.lua_get([[agent.stderr]]))
end

T["Agent"]["functions"]["can populate stdout"] = function()
  child.lua([[
     -- Prevent stdout from being cleared out
     function agent:reset()
       return nil
     end
    local tools = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func",
        },
      },
      {
        ["function"] = {
          arguments = { data = "Data 2" },
          name = "func",
        },
      },
    }
    agent:execute(chat, tools)
   ]])

  h.eq({ "Data 1", "Data 2" }, child.lua_get([[agent.stdout]]))
end

return T
