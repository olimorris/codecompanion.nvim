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
        _G.TEST_TMPFILE = '/tests/stubs/cc_test_file.txt'
        _G.TEST_TMPFILE_ABSOLUTE = vim.fs.joinpath(vim.fn.getcwd(), _G.TEST_TMPFILE)

        -- ensure no leftover from previous run
        pcall(vim.loop.fs_unlink, _G.TEST_TMPFILE_ABSOLUTE)

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

T["insert_edit_into_file tool edit a file"] = function()
  child.lua([[
      -- create initial file
      local initial = "line1\nline2\nline3"
      local ok = vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE_ABSOLUTE)
      assert(ok == 0)

      local tool = {
        {
          ["function"] = {
            name = "insert_edit_into_file",
            arguments = string.format('{"filepath": "%s", "explanation": "Some edit", "code": "*** Begin Patch\\nline1\\n-line2\\n+new_line2\\nline3\\n*** End Patch"}', _G.TEST_TMPFILE)
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE_ABSOLUTE)")
  h.eq(output, { "line1", "new_line2", "line3" }, "File was not updated")
end

T["insert_edit_into_file tool regex"] = function()
  child.lua([[
      -- create initial file
      local initial = "line1\nline2\nline3"
      local ok = vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE_ABSOLUTE)
      assert(ok == 0)
      local tool = {
        {
          ["function"] = {
            name = "insert_edit_into_file",
            arguments = string.format('{"filepath": "%s", "code": "*** Begin Patch\\n-line2\\n*** End Patch\\n"}', _G.TEST_TMPFILE)
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE_ABSOLUTE)")
  h.eq(output, { "line1", "line3" }, "File was not updated")
end

T["insert_edit_into_file tool update from fixtures"] = function()
  child.lua([[
       -- read initial file from fixture
       local initial = vim.fn.readfile("tests/fixtures/files-input-1.html")
       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE_ABSOLUTE)
       assert(ok == 0)

       -- read contents for the tool from fixtures
       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-1.1.patch"), "\n")
       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
       local tool = {
         {
           ["function"] = {
             name = "insert_edit_into_file",
             arguments = arguments
           },
         },
       }
       agent:execute(chat, tool)
       vim.wait(200)
     ]])

  -- Test that the file was updated as per the output fixture
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE_ABSOLUTE)")
  local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-1.1.html')")
  h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
end
--
-- T["insert_edit_into_file tool update multiple @@"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-1.html")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-1.2.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-1.2.html')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end
--
-- T["insert_edit_into_file tool update empty lines"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-1.html")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-1.3.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-1.3.html')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end
--
-- T["insert_edit_into_file tool multiple patches"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-1.html")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-1.4.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-1.4.html')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end
--
-- T["insert_edit_into_file tool update multiple continuation"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-2.html")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-2.1.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-2.1.html')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end
--
-- T["insert_edit_into_file tool update spaces"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-2.html")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-2.2.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-2.2.html')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end
--
-- T["insert_edit_into_file tool update html spaces flexible"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-3.html")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-3.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-3.html')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end
--
-- T["insert_edit_into_file tool update html line breaks"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-4.html")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-4.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-4.html')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end
--
-- T["insert_edit_into_file tool update lua dashes"] = function()
--   child.lua([[
--       -- read initial file from fixture
--       local initial = vim.fn.readfile("tests/fixtures/files-input-5.lua")
--       local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE)
--       assert(ok == 0)
--       -- read contents for the tool from fixtures
--       local content = table.concat(vim.fn.readfile("tests/fixtures/files-diff-5.patch"), "\n")
--       local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, code = content })
--       local tool = {
--         {
--           ["function"] = {
--             name = "insert_edit_into_file",
--             arguments = arguments
--           },
--         },
--       }
--       agent:execute(chat, tool)
--       vim.wait(200)
--     ]])
--
--   -- Test that the file was updated as per the output fixture
--   local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
--   local expected = child.lua_get("vim.fn.readfile('tests/fixtures/files-output-5.lua')")
--   h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))
-- end

return T
