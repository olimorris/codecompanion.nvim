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
T["Agent"]["user approval"] = new_set()

T["Agent"]["user approval"]["prompts a user when tool requires approval"] = function()
  child.lua([[
    -- Mock vim.ui.select to capture what gets called
    local original_select = vim.ui.select
    _G.ui_called = false
    _G.ui_prompt = nil
    _G.ui_choices = nil

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      _G.ui_prompt = opts.prompt
      _G.ui_choices = choices
      callback("Yes") -- User approves
    end

    local tools = {
      {
        ["function"] = {
          name = "func_approval",
          arguments = { data = "Test Data" },
        },
      },
    }
    agent:execute(chat, tools)

    -- Restore original
    vim.ui.select = original_select
  ]])

  -- Check that UI was called with expected values
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Run the func_approval tool?", child.lua_get([[_G.ui_prompt]]))
  h.eq({ "Yes", "No", "Cancel" }, child.lua_get([[_G.ui_choices]]))

  -- Check that tool executed after approval
  h.eq("Test Data", child.lua_get([[_G._test_func]]))
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))
end

T["Agent"]["user approval"]["approval can be conditionally set - true in this case"] = function()
  child.lua([[
    -- Mock vim.ui.select to capture what gets called
    local original_select = vim.ui.select
    _G.ui_called = false

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("Yes") -- User approves
    end

    local tools = {
      {
        ["function"] = {
          name = "func_approval2",
          arguments = { data = "Approve" },
        },
      },
    }
    agent:execute(chat, tools)

    -- Restore original
    vim.ui.select = original_select
  ]])

  -- Check that UI was called with expected values
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))
end

T["Agent"]["user approval"]["approval can be conditionally set - false in this case"] = function()
  child.lua([[
    -- Mock vim.ui.select to capture what gets called
    local original_select = vim.ui.select
    _G.ui_called = false

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("Yes") -- User approves
    end

    local tools = {
      {
        ["function"] = {
          name = "func_approval2",
          arguments = { data = "Reject" },
        },
      },
    }
    agent:execute(chat, tools)

    -- Restore original
    vim.ui.select = original_select
  ]])

  h.eq(false, child.lua_get([[_G.ui_called]]))
end

T["Agent"]["user approval"]["approval can be rejected"] = function()
  child.lua([[
    -- Mock vim.ui.select to capture what gets called
    local original_select = vim.ui.select
    _G.ui_called = true

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("No") -- User approves
    end

    local tools = {
      {
        ["function"] = {
          name = "func_approval",
          arguments = { data = "Test Data" },
        },
      },
    }
    agent:execute(chat, tools)

    -- Restore original
    vim.ui.select = original_select
  ]])

  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Setup->Rejected", child.lua_get([[_G._test_order]]))
end

return T
