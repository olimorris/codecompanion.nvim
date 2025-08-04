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

return T
