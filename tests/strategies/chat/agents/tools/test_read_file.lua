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
        _G.TEST_DIR = 'tests/stubs/read_file'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.TEST_DIR)

        _G.TEST_TMPFILE = "cc_readfile_test.txt"
        _G.TEST_TMPFILE_ABSOLUTE = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, _G.TEST_TMPFILE)

        -- Create test directory structure
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE, 'p')

        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()
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

T["can read lines from a file"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)
    local contents = { "alpha", "beta", "gamma" }

    local ok = vim.fn.writefile(contents, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    local tool = {
      {
        ["function"] = {
          name = "read_file",
          arguments = string.format('{"filepath": "%s", "start_line_number_base_zero": 0, "end_line_number_base_zero": 1}', vim.fs.joinpath(_G.TEST_DIR, _G.TEST_TMPFILE))
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
    --require('tests.log')
    vim.uv.chdir(_G.TEST_CWD)

    local contents = { "alpha", "beta", "gamma" }
    local ok = vim.fn.writefile(contents, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    local tool = {
      {
        ["function"] = {
          name = "read_file",
          arguments = string.format('{"filepath": "%s", "start_line_number_base_zero": 0, "end_line_number_base_zero": -1}', vim.fs.joinpath(_G.TEST_DIR, _G.TEST_TMPFILE))
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
T["clamps end_line_number_base_zero to file length if it is too large"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)
    local contents = { "one", "two", "three", "four", "five" }
    local ok = vim.fn.writefile(contents, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    -- end_line_number_base_zero is way beyond file length (file has 5 lines, 0-based: 0-4)
    local tool = {
      {
        ["function"] = {
          name = "read_file",
          arguments = string.format(
            '{"filepath": "%s", "start_line_number_base_zero": 1, "end_line_number_base_zero": 10}',
            vim.fs.joinpath(_G.TEST_DIR, _G.TEST_TMPFILE)
          )
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("two", string.match(output, "two"))
  h.eq("three", string.match(output, "three"))
  h.eq("four", string.match(output, "four"))
  h.eq("five", string.match(output, "five"))
  h.not_eq("one", string.match(output, "one")) -- since we started at line 1
end

T["can only read files that exist"] = function()
  child.lua([[
    --require("tests.log")
    local tool = {
      {
        ["function"] = {
          name = "read_file",
          arguments = string.format('{"filepath": "%s", "start_line_number_base_zero": 0, "end_line_number_base_zero": -1}', "/does/not/exist.txt")
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("Error reading", output)
end

return T
