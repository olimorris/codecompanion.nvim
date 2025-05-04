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
          arguments = string.format('{"action": "CREATE", "path": "%s", "contents": "import pygame\\nimport time\\nimport random\\n"}', _G.TEST_TMPFILE)
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

T["files tool update"] = function()
  child.lua([[
      -- create initial file
      local initial = "line1\nline2\nline3"
      local ok = vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)
      assert(ok == 0)
      local tool = {
        {
          ["function"] = {
            name = "files",
            arguments = string.format('{"action": "UPDATE", "path": "%s", "contents": "*** Begin Patch\\nline1\\n-line2\\n+new_line2\\nline3\\n*** End Patch"}', _G.TEST_TMPFILE)
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "line1", "new_line2", "line3" }, "File was not updated")
end

T["files tool regex"] = function()
  child.lua([[
      -- create initial file
      local initial = "line1\nline2\nline3"
      local ok = vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)
      assert(ok == 0)
      local tool = {
        {
          ["function"] = {
            name = "files",
            arguments = string.format('{"action": "UPDATE", "path": "%s", "contents": "*** Begin Patch\\n-line2\\n*** End Patch\\n"}', _G.TEST_TMPFILE)
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "line1", "line3" }, "File was not updated")
end

T["files tool update from fixtures"] = function()
  child.lua([[
      -- read initial file from fixture
      local initial = vim.fn.readfile("tests/fixtures/files-input-1.html")
      local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
      assert(ok == 0)
      -- read contents for the tool from fixtures
      local patch_contents = table.concat(vim.fn.readfile("tests/fixtures/files-diff-1.patch"), "\n")
      local arguments = vim.json.encode({ action = "UPDATE", path = _G.TEST_TMPFILE, contents = patch_contents })
      local tool = {
        {
          ["function"] = {
            name = "files",
            arguments = arguments
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated as per the output fixture
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-1.html')")
  h.eq(output, expected, "File was not updated according to fixtures")
end

T["files tool update multiple @@"] = function()
  child.lua([[
      -- read initial file from fixture
      local initial = vim.fn.readfile("tests/fixtures/files-input-1.html")
      local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
      assert(ok == 0)
      -- read contents for the tool from fixtures
      local patch_contents = table.concat(vim.fn.readfile("tests/fixtures/files-diff-2.patch"), "\n")
      local arguments = vim.json.encode({ action = "UPDATE", path = _G.TEST_TMPFILE, contents = patch_contents })
      local tool = {
        {
          ["function"] = {
            name = "files",
            arguments = arguments
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated as per the output fixture
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-2.html')")
  h.eq(output, expected, "File was not updated according to fixtures")
end

T["files tool update empty lines"] = function()
  child.lua([[
      -- read initial file from fixture
      local initial = vim.fn.readfile("tests/fixtures/files-input-1.html")
      local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
      assert(ok == 0)
      -- read contents for the tool from fixtures
      local patch_contents = table.concat(vim.fn.readfile("tests/fixtures/files-diff-3.patch"), "\n")
      local arguments = vim.json.encode({ action = "UPDATE", path = _G.TEST_TMPFILE, contents = patch_contents })
      local tool = {
        {
          ["function"] = {
            name = "files",
            arguments = arguments
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated as per the output fixture
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-3.html')")
  h.eq(output, expected, "File was not updated according to fixtures")
end

T["files tool update multiple continuation"] = function()
  child.lua([[
      -- read initial file from fixture
      local initial = vim.fn.readfile("tests/fixtures/files-input-4.html")
      local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
      assert(ok == 0)
      -- read contents for the tool from fixtures
      local patch_contents = table.concat(vim.fn.readfile("tests/fixtures/files-diff-4.patch"), "\n")
      local arguments = vim.json.encode({ action = "UPDATE", path = _G.TEST_TMPFILE, contents = patch_contents })
      local tool = {
        {
          ["function"] = {
            name = "files",
            arguments = arguments
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated as per the output fixture
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-4.html')")
  h.eq(output, expected, "File was not updated according to fixtures")
end

T["files tool read"] = function()
  child.lua([[
    -- Create a test file with known contents
    local contents = { "alpha", "beta", "gamma" }
    local ok = vim.fn.writefile(contents, _G.TEST_TMPFILE)
    assert(ok == 0)
    local tool = {
      {
        ["function"] = {
          name = "files",
          arguments = string.format('{"action": "READ", "path": "%s", "contents": null}', _G.TEST_TMPFILE)
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
