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
T["Tools"]["user approval"] = new_set()

T["Tools"]["user approval"]["prompts a user when tool requires approval"] = function()
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

    local tool_calls = {
      {
        ["function"] = {
          name = "func_approval",
          arguments = { data = "Test Data" },
        },
      },
    }
    tools:execute(chat, tool_calls)

    -- Restore original
    vim.ui.select = original_select
  ]])

  -- Check that UI was called with expected values
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Run the func_approval tool?", child.lua_get([[_G.ui_prompt]]))
  h.eq({ "Yes", "No", "No with feedback", "Cancel" }, child.lua_get([[_G.ui_choices]]))

  -- Check that tool executed after approval
  h.eq("Test Data", child.lua_get([[_G._test_func]]))
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))
end

T["Tools"]["user approval"]["approval can be conditionally set - true in this case"] = function()
  child.lua([[
    -- Mock vim.ui.select to capture what gets called
    local original_select = vim.ui.select
    _G.ui_called = false

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("Yes") -- User approves
    end

    local tool_calls = {
      {
        ["function"] = {
          name = "func_approval2",
          arguments = { data = "Approve" },
        },
      },
    }
    tools:execute(chat, tool_calls)

    -- Restore original
    vim.ui.select = original_select
  ]])

  -- Check that UI was called with expected values
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))
end

T["Tools"]["user approval"]["approval can be conditionally set - false in this case"] = function()
  child.lua([[
    -- Mock vim.ui.select to capture what gets called
    local original_select = vim.ui.select
    _G.ui_called = false

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("Yes") -- User approves
    end

    local tool_calls = {
      {
        ["function"] = {
          name = "func_approval2",
          arguments = { data = "Reject" },
        },
      },
    }
    tools:execute(chat, tool_calls)

    -- Restore original
    vim.ui.select = original_select
  ]])

  h.eq(false, child.lua_get([[_G.ui_called]]))
end

T["Tools"]["user approval"]["approval can be rejected"] = function()
  child.lua([[
    -- Mock vim.ui.select to capture what gets called
    local original_select = vim.ui.select
    _G.ui_called = true

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("No") -- User approves
    end

    local tool_calls = {
      {
        ["function"] = {
          name = "func_approval",
          arguments = { data = "Test Data" },
        },
      },
    }
    tools:execute(chat, tool_calls)

    -- Restore original
    vim.ui.select = original_select
  ]])

  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Setup->Rejected", child.lua_get([[_G._test_order]]))
end

T["Tools"]["user approval"]["approval can be rejected with feedback - custom handler"] = function()
  child.lua([[
    -- Mock vim.ui.select and vim.ui.input to capture what gets called
    local original_select = vim.ui.select
    local original_input = vim.ui.input
    _G.ui_called = false
    _G.input_called = false
    _G.feedback_prompt = nil

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("No with feedback") -- User rejects with feedback
    end

    vim.ui.input = function(opts, callback)
      _G.input_called = true
      _G.feedback_prompt = opts.prompt
      callback("This tool seems unsafe to run") -- User provides feedback
    end

    -- Reset test feedback global
    _G._test_feedback = nil

    local tool_calls = {
      {
        ["function"] = {
          name = "func_approval",
          arguments = { data = "Test Data" },
        },
      },
    }
    tools:execute(chat, tool_calls)

    -- Restore originals
    vim.ui.select = original_select
    vim.ui.input = original_input
  ]])

  -- Check that both UI functions were called
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq(true, child.lua_get([[_G.input_called]]))
  h.eq("Feedback (why was this tool rejected?): ", child.lua_get([[_G.feedback_prompt]]))

  -- Check that the feedback was properly passed to the tool's rejected handler
  local feedback = child.lua_get([[_G._test_feedback]])
  h.eq("This tool seems unsafe to run", feedback)

  -- Check that tool was properly rejected
  h.eq("Setup->Rejected", child.lua_get([[_G._test_order]]))
end

T["Tools"]["user approval"]["approval can be rejected with feedback - default handler"] = function()
  child.lua([[
    -- Mock vim.ui.select and vim.ui.input to capture what gets called
    local original_select = vim.ui.select
    local original_input = vim.ui.input
    _G.ui_called = false
    _G.input_called = false
    _G.feedback_prompt = nil
    _G.default_rejection_message = nil

    vim.ui.select = function(choices, opts, callback)
      _G.ui_called = true
      callback("No with feedback") -- User rejects with feedback
    end

    vim.ui.input = function(opts, callback)
      _G.input_called = true
      _G.feedback_prompt = opts.prompt
      callback("This tool looks dangerous") -- User provides feedback
    end

    -- Mock add_tool_output to capture the default rejection message
    local original_add_tool_output = chat.add_tool_output
    chat.add_tool_output = function(self, tool, message)
      _G.default_rejection_message = message
      return original_add_tool_output(self, tool, message)
    end

    -- Temporarily remove the rejected handler from func_approval2 to test default handler
    local func_approval2_tool = require("tests.strategies.chat.tools.catalog.stubs.func_approval2")
    local original_rejected = func_approval2_tool.output.rejected
    func_approval2_tool.output.rejected = nil

    local tool_calls = {
      {
        ["function"] = {
          name = "func_approval2",
          arguments = { data = "NoApprove" }, -- This bypasses conditional approval
        },
      },
    }
    tools:execute(chat, tool_calls)

    -- Restore everything
    func_approval2_tool.output.rejected = original_rejected
    vim.ui.select = original_select
    vim.ui.input = original_input
    chat.add_tool_output = original_add_tool_output
  ]])

  -- Check that both UI functions were called
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq(true, child.lua_get([[_G.input_called]]))
  h.eq("Feedback (why was this tool rejected?): ", child.lua_get([[_G.feedback_prompt]]))

  -- Check that the default rejection message includes feedback
  local rejection_message = child.lua_get([[_G.default_rejection_message]])
  h.expect_contains("User rejected `func_approval2`", rejection_message)
  h.expect_contains("This tool looks dangerous", rejection_message)
end

return T
