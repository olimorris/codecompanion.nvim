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

        ui_utils = require("codecompanion.utils.ui")
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
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      _G.ui_called = true
      _G.ui_prompt = opts.prompt
      -- Auto-select "Approve" (g2)
      for _, choice in ipairs(opts.choices) do
        if choice.keymap == "g2" then
          choice.callback()
          return
        end
      end
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
  ]])

  -- Check that approval prompt was called with expected values
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Run the func_approval tool?", child.lua_get([[_G.ui_prompt]]))

  -- Check that tool executed after approval
  h.eq("Test Data", child.lua_get([[_G._test_func]]))
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))
end

T["Tools"]["user approval"]["approval can be conditionally set - true in this case"] = function()
  child.lua([[
    _G.ui_called = false

    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      _G.ui_called = true
      -- Auto-select "Approve" (g2)
      for _, choice in ipairs(opts.choices) do
        if choice.keymap == "g2" then
          choice.callback()
          return
        end
      end
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
  ]])

  -- Check that approval prompt was called
  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Setup->Success->Exit", child.lua_get([[_G._test_order]]))
end

T["Tools"]["user approval"]["approval can be conditionally set - false in this case"] = function()
  child.lua([[
    _G.ui_called = false

    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      _G.ui_called = true
      opts.choices[1].callback()
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
  ]])

  h.eq(false, child.lua_get([[_G.ui_called]]))
end

T["Tools"]["user approval"]["approval can be rejected"] = function()
  child.lua([[
    _G.ui_called = false

    -- Stub vim.ui.input for rejection reason
    vim.ui.input = function(_, cb)
      cb("Rejected")
    end

    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      _G.ui_called = true
      -- Auto-select "Reject" (g3)
      for _, choice in ipairs(opts.choices) do
        if choice.keymap == "g3" then
          choice.callback()
          return
        end
      end
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
  ]])

  h.eq(true, child.lua_get([[_G.ui_called]]))
  h.eq("Setup->Rejected", child.lua_get([[_G._test_order]]))
end

T["Tools"]["user approval"]["rejection reason is passed to LLM"] = function()
  child.lua([[
    -- Stub vim.ui.input for rejection reason
    vim.ui.input = function(_, cb)
      cb("this is my rejection reason")
    end

    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      -- Auto-select "Reject" (g3)
      for _, choice in ipairs(opts.choices) do
        if choice.keymap == "g3" then
          choice.callback()
          return
        end
      end
    end

    local tool_calls = {
      {
        ["function"] = {
          name = "func_approval",
          arguments = { data = "Test Data" },
        },
      },
    }
    _G._initial_count = #chat.messages
    tools:execute(chat, tool_calls)
    vim.wait(2000, function()
      return #chat.messages > _G._initial_count
    end)
  ]])

  h.eq(true, child.lua_get("#chat.messages > _G._initial_count"), "rejection message was not added to chat")

  local last_msg = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_match(last_msg, "this is my rejection reason")
end

return T
