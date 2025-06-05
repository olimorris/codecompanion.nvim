local h = require("tests.helpers")

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

T["can read lines from a file"] = function()
  child.lua([[
    local contents = { "alpha", "beta", "gamma" }
    local ok = vim.fn.writefile(contents, _G.TEST_TMPFILE)
    assert(ok == 0)

    local tool = {
      {
        ["function"] = {
          name = "read_file",
          arguments = string.format('{"filepath": "%s", "start_line_number_base_zero": 0, "end_line_number_base_zero": 1}', _G.TEST_TMPFILE)
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("alpha", string.match(output, "alpha"))
  h.eq("beta", string.match(output, "beta"))
  h.not_eq("gamma", string.match(output, "gamma"))
end

T["can read all of the file"] = function()
  child.lua([[
    require('tests.log')
    local contents = { "alpha", "beta", "gamma" }
    local ok = vim.fn.writefile(contents, _G.TEST_TMPFILE)
    assert(ok == 0)

    local tool = {
      {
        ["function"] = {
          name = "read_file",
          arguments = string.format('{"filepath": "%s", "start_line_number_base_zero": 0, "end_line_number_base_zero": -1}', _G.TEST_TMPFILE)
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("alpha", string.match(output, "alpha"))
  h.eq("beta", string.match(output, "beta"))
  h.eq("gamma", string.match(output, "gamma"))
end

return T
