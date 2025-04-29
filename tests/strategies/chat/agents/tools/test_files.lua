local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.o.statusline = ""
      child.o.laststatus = 0
      child.lua([[
        _G.TEST_TMPFILE = vim.fn.stdpath('cache') .. '/codecompanion/tests/cc_test_file.txt'

        -- ensure no leftover from previous run
        pcall(vim.loop.fs_unlink, _G.TEST_TMPFILE)

        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.loop.fs_unlink, _G.TEST_TMPFILE)
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["files tool"] = function()
  child.lua([[
    --require("tests.log")
    local tool = {
      {
        ["function"] = {
          name = "files",
          arguments = string.format('{"action": "create", "path": "%s", "contents": "import pygame\\nimport time\\nimport random\\n"}', _G.TEST_TMPFILE)
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  -- Test that the file was created
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "import pygame", "import time", "import random" }, "File was not created")

  -- expect.reference_screenshot(child.get_screenshot())
end

return T
