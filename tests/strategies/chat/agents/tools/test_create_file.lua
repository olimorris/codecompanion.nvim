local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua([[
        _G.TEST_TMPFILE = '/tests/stubs/cc_test_file.txt'
        _G.TEST_TMPFILE_ABSOLUTE = vim.fs.joinpath(vim.fn.getcwd(), _G.TEST_TMPFILE)

        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.loop.fs_unlink, _G.TEST_TMPFILE_ABSOLUTE)
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["can create files"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "create_file",
          arguments = string.format('{"filepath": "%s", "content": "import pygame\\nimport time\\nimport random\\n"}', _G.TEST_TMPFILE)
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE_ABSOLUTE)")
  h.eq(output, { "import pygame", "import time", "import random" }, "File was not created")
end

return T
