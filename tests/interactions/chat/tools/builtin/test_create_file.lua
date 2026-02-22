local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua([[
        -- Setup test directory structure
        _G.TEST_CWD = vim.fn.tempname()
        _G.TEST_DIR = 'tests/stubs/create_file'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.TEST_DIR)

        _G.TEST_TMPFILE = "cc_test_file.txt"
        _G.TEST_TMPFILE_ABSOLUTE = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, _G.TEST_TMPFILE)

        -- Create test directory structure
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE, 'p')

        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.fn.delete, _G.TEST_CWD, 'rf')
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["can create files"] = function()
  child.lua([[
    -- Change to the temporary directory (like test_read_file.lua does)
    vim.uv.chdir(_G.TEST_CWD)

    local tool = {
      {
        ["function"] = {
          name = "create_file",
          -- Use absolute path
          arguments = string.format('{"filepath": "%s", "content": "import pygame\\nimport time\\nimport random\\n"}', _G.TEST_TMPFILE_ABSOLUTE)
        },
      },
    }
    tools:execute(chat, tool)

    -- Wait for file to be created with a condition
    local file_created = vim.wait(5000, function()
      local stat = vim.loop.fs_stat(_G.TEST_TMPFILE_ABSOLUTE)
      return stat ~= nil
    end, 50)

    if not file_created then
      error(string.format("File was not created at: %s", _G.TEST_TMPFILE_ABSOLUTE))
    end
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE_ABSOLUTE)")
  h.eq(output, { "import pygame", "import time", "import random" }, "File was not created")
end

return T
