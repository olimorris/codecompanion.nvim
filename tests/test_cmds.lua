local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.o.statusline = ""
      child.o.laststatus = 0
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

return T
