local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        h.setup_plugin()
      ]])
    end,
    post_once = child.stop,
  },
})

T["cmds"] = new_set()
T["cmds"][":CodeCompanionChat"] = function()
  child.lua([[
    -- Mock the submit function
    local original = h.mock_submit("This is a mocked response: 1 + 1 = 2")

    -- Run the command
    vim.cmd("CodeCompanionChat this is a test, what is 1 + 1?")
    vim.wait(100)

    -- Restore the original function
    h.restore_submit(original)
  ]])
  expect.reference_screenshot(child.get_screenshot())
end

T["cmds"][":CodeCompanionChat Toggle"] = function()
  child.cmd([[tabnew]])
  child.cmd([[CodeCompanionChat Toggle]])
  expect.reference_screenshot(child.get_screenshot())
end

T["cmds"]["sticky chat window"] = function()
  child.lua([[
    require('codecompanion').setup({
      display = {
        chat = {
          window = {
            layout = "vertical",
            sticky = true
          }
        }
      }
    })
    vim.cmd("CodeCompanionChat")
    vim.cmd("tabnew")
  ]])

  -- expect.reference_screenshot(child.get_screenshot())
  -- window opened
  h.eq(true, child.lua_get("require('codecompanion').last_chat().ui:is_visible()"))
  -- window opened in the current tab (in other words, NOT in NON_CURRENT tab)
  h.eq(false, child.lua_get("require('codecompanion').last_chat().ui:is_visible_non_curtab()"))
end
-- Verify that CodeCompanionComplete is registered as a user command
T["cmds"][":CodeCompanionComplete should be registered"] = function()
  child.lua([[
    local cmds = vim.api.nvim_get_commands({ builtin = false })
    assert(cmds["CodeCompanionComplete"] ~= nil)
  ]])
end

-- Ensure CodeCompanionComplete invokes the inline strategy
T["cmds"][":CodeCompanionComplete invokes inline"] = function()
  child.lua([[
    local called = false
    require('codecompanion').inline = function(opts) called = true end
    vim.cmd("CodeCompanionComplete")
    assert(called)
  ]])
end

-- End-to-end test for CodeCompanionComplete: simple insertion at cursor
T["cmds"][":CodeCompanionComplete end-to-end simple insertion"] = function()
  child.lua([[
    local h = require('tests.helpers')
    h.setup_plugin()
    -- Prepare a Python buffer with a cursor placeholder
    vim.bo.filetype = 'py'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      '# print "Hello World!"',
      'print(',
    })
    -- Place cursor after the opening parenthesis on line 2
    vim.api.nvim_win_set_cursor(0, {2, 6})
    -- Mock inline to perform the expected insertion
    require('codecompanion').inline = function(opts)
      vim.api.nvim_buf_set_lines(0, 1, 2, false, {
        'print("Hello World!")',
      })
    end
    -- call command
    vim.cmd('CodeCompanionComplete')
  ]])
  -- Verify buffer content was updated as expected
  local lines = child.lua_get("require('tests.helpers').get_buf_lines(0)")
  h.eq({ '# print "Hello World!"', 'print("Hello World!")' }, lines)
end

return T
