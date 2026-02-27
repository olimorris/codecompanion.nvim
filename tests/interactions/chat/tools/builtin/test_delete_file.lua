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
        _G.TEST_DIR = 'tests/stubs/delete_file'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.TEST_DIR)

        _G.TEST_TMPFILE = "cc_test_delete.txt"
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

T["can delete a file"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)

    -- Create a test file first
    local ok = vim.fn.writefile({ "test content" }, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    -- Verify the file exists
    local stat_before = vim.loop.fs_stat(_G.TEST_TMPFILE_ABSOLUTE)
    assert(stat_before ~= nil, "File was not created")

    local tool = {
      {
        ["function"] = {
          name = "delete_file",
          arguments = string.format('{"filepath": "%s"}', _G.TEST_TMPFILE_ABSOLUTE)
        },
      },
    }
    tools:execute(chat, tool)

    -- Wait for file to be deleted
    local file_deleted = vim.wait(300, function()
      local stat = vim.loop.fs_stat(_G.TEST_TMPFILE_ABSOLUTE)
      return stat == nil
    end, 50)

    if not file_deleted then
      error(string.format("File was not deleted at: %s", _G.TEST_TMPFILE_ABSOLUTE))
    end
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("Deleted", output)
end

T["cannot delete a directory"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)

    -- Create a test subdirectory
    local subdir = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, "test_subdir")
    vim.fn.mkdir(subdir, 'p')

    local tool = {
      {
        ["function"] = {
          name = "delete_file",
          arguments = string.format('{"filepath": "%s"}', vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, "test_subdir"))
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("directory", output)
end

T["cannot delete a file that does not exist"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)

    local tool = {
      {
        ["function"] = {
          name = "delete_file",
          arguments = string.format('{"filepath": "%s"}', vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, "nonexistent.txt"))
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("Failed deleting", output)
end

return T
