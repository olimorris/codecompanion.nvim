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

T["File"] = new_set()

T["File"]["insert_edit_into_file tool edit a file"] = function()
  child.lua([[
      -- create initial file
      local initial = "line1\nline2\nline3"
      local ok = vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE_ABSOLUTE)
      assert(ok == 0)

      local tool = {
        {
          ["function"] = {
            name = "insert_edit_into_file",
            arguments = string.format('{"filepath": "%s", "explanation": "...", "code": "*** Begin Patch\\nline1\\n-line2\\n+new_line2\\nline3\\n*** End Patch"}', _G.TEST_TMPFILE)
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

T["File"]["insert_edit_into_file tool add to end of a file"] = function()
  child.lua([[
      -- create initial file
      local initial = "line1"
			-- the writefile function adds an extra '\n' at the end. We then use a Patch that keeps that empty line so that we can really test the additon of something at the end of the file. Otherwise this test will pass even before the fix.
      local ok = vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE_ABSOLUTE)
      assert(ok == 0)

      local tool = {
        {
          ["function"] = {
            name = "insert_edit_into_file",
            arguments = string.format('{"filepath": "%s", "explanation": "...", "code": "*** Begin Patch\\nline1\\n\\n+new_line2\\n*** End Patch"}', _G.TEST_TMPFILE)
          },
        },
      }
      agent:execute(chat, tool)
      vim.wait(200)
    ]])

  -- Test that the file was updated
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE_ABSOLUTE)")
  h.eq(output, { "line1", "", "new_line2" }, "File was not updated")
end

T["File"]["insert_edit_into_file tool regex"] = function()
  child.lua([[
      -- create initial file
      local initial = "line1\nline2\nline3"
      local ok = vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE_ABSOLUTE)
      assert(ok == 0)
      local tool = {
        {
          ["function"] = {
            name = "insert_edit_into_file",
            arguments = string.format('{"filepath": "%s", "explanation": "...", "code": "*** Begin Patch\\n-line2\\n*** End Patch\\n"}', _G.TEST_TMPFILE)
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

T["Buffer"] = new_set()

T["Buffer"]["insert_edit_into_file tool edits buffers"] = function()
  child.lua([[
      -- read initial file from fixture
      local initial = vim.fn.readfile("tests/fixtures/buffers-input-1.lua")
      local ok = vim.fn.writefile(initial, _G.TEST_TMPFILE_ABSOLUTE)
      assert(ok == 0)

      -- load the file into a buffer
      _G.bufnr = vim.fn.bufadd(_G.TEST_TMPFILE_ABSOLUTE)

      -- read contents for the tool from fixtures
      local content = table.concat(vim.fn.readfile("tests/fixtures/buffers-diff-1.patch"), "\n")
      local arguments = vim.json.encode({ filepath = _G.TEST_TMPFILE, explanation = "...", code = content })

      local tool = {
        {
          ["function"] = {
            name = "insert_edit_into_file",
            arguments = arguments
          },
        },
      }
      agent:execute(chat, tool)
      vim.cmd("buffer " .. _G.bufnr)
      vim.wait(200)
    ]])

  -- Test that the file was updated as per the output fixture
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE_ABSOLUTE)")
  local expected = child.lua_get("vim.fn.readfile('tests/fixtures/buffers-output-1.lua')")
  h.eq_info(output, expected, child.lua_get("chat.messages[#chat.messages].content"))

  -- Check that the buffer was updated
  local lines = child.lua([[
    local log = require("codecompanion.utils.log")
    local lines = h.get_buf_lines(_G.bufnr)
    return lines
  ]])
  h.eq(lines[2], '  return "CodeCompanion"')
end

return T
