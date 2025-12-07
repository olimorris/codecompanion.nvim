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
        chat, tools = h.setup_chat_buffer()

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

T["Tools"] = new_set()
T["Tools"]["functions"] = new_set()

T["Tools"]["functions"]["can run"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    local tool_call = {
      {
        ["function"] = {
          name = "func",
          arguments = { data = "Data 1" },
        },
      },
    }
    tools:execute(chat, tool_call)
  ]])

  -- Test order
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the function was called
  h.eq("Data 1", child.lua_get([[_G._test_func]]))
end

T["Tools"]["functions"]["can run functions of the same name consecutively"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    --require("tests.log")
    local tool_call = {
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
    tools:execute(chat, tool_call)
  ]])

  -- Test order
  h.eq("Setup->Success->ExitSetup->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the function was called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Tools"]["functions"]["can run functions of the same name consecutively and not reuse handlers"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    --require("tests.log")
    local tool_call = {
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
    tools:execute(chat, tool_call)
  ]])

  -- Test order
  h.eq("Setup->Success->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the function was called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Tools"]["functions"]["can run functions of a different name consecutively"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    local tool_call = {
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
    tools:execute(chat, tool_call)
  ]])

  -- Test order
  h.eq("Setup->Success->Exit->Setup->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the tools were called
  h.eq("Data 1 Data 2", child.lua_get([[_G._test_func]]))
end

T["Tools"]["functions"]["calls output.success"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_output]]))

  child.lua([[
    local tool_call = {
      {
        ["function"] = {
          name = "func",
          arguments = { data = "Data 1" },
        },
      },
    }
    tools:execute(chat, tool_call)
  ]])

  -- Test that the function was called
  h.eq("Ran with success", child.lua_get([[_G._test_output]]))
end

T["Tools"]["functions"]["can pass input to the next function"] = function()
  h.eq(vim.NIL, child.lua_get([[_G._test_func]]))

  child.lua([[
    local tool_call = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_consecutive",
        },
      },
    }
    tools:execute(chat, tool_call)
   ]])

  h.eq("Setup->Success->Success->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the functions was called
  h.eq("Data 1 Data 1", child.lua_get([[_G._test_func]]))
end

T["Tools"]["functions"]["can handle errors"] = function()
  child.lua([[
    local tool_call = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_error",
        },
      },
    }
    tools:execute(chat, tool_call)
  ]])

  h.eq("Setup->Error->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the `output.error` handler was called
  h.eq("<error>Something went wrong</error>", child.lua_get([[_G._test_output]]))
end

T["Tools"]["functions"]["can return errors"] = function()
  child.lua([[
    local tool_call = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_return_error",
        },
      },
    }
    tools:execute(chat, tool_call)
   ]])

  h.eq("Setup->Success->Error->Exit", child.lua_get([[_G._test_order]]))

  -- Test that the `output.error` handler was called
  h.eq("<error>This will throw an error</error>", child.lua_get([[_G._test_output]]))
end

T["Tools"]["functions"]["can populate stderr and halt execution"] = function()
  child.lua([[
     -- Prevent stderr from being cleared out
     function tools:reset()
       return nil
     end
    local tool_call = {
      {
        ["function"] = {
          arguments = { data = "Data 1" },
          name = "func_error",
        },
      },
    }
    tools:execute(chat, tool_call)
   ]])

  -- Test that stderr is updated on the tool system, only once
  h.eq({ "Something went wrong" }, child.lua_get([[tools.stderr]]))
end

T["Tools"]["functions"]["can populate stdout"] = function()
  child.lua([[
     -- Prevent stdout from being cleared out
     function tools:reset()
       return nil
     end
    local tool_call = {
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
    tools:execute(chat, tool_call)
   ]])

  h.eq({ "Data 1", "Data 2" }, child.lua_get([[tools.stdout]]))
end

return T
