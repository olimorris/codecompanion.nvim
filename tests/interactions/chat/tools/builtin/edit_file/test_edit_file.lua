local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.TEST_FILE = vim.fn.tempname() .. ".lua"
        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        _G.run_edit = function(args)
          args.filepath = _G.TEST_FILE
          args.replace_all = args.replace_all or false
          tools:execute(chat, { { ["function"] = { name = "edit_file", arguments = vim.json.encode(args) } } })
          vim.wait(10)
          return chat.messages[#chat.messages].content
        end

        _G.write_raw = function(content)
          local f = assert(io.open(_G.TEST_FILE, "wb"))
          f:write(content)
          f:close()
        end

        _G.read_raw = function()
          local f = assert(io.open(_G.TEST_FILE, "rb"))
          local content = f:read("*a")
          f:close()
          return content
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.uv.fs_unlink, _G.TEST_FILE)
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["Edit File"] = new_set()

T["Edit File"]["edits a file"] = function()
  child.lua([[
    _G.write_raw("local x = 1\nlocal y = 2\n")
    _G.run_edit({ old_string = "local y = 2", new_string = "local y = 3" })
  ]])
  h.eq("local x = 1\nlocal y = 3\n", child.lua_get("_G.read_raw()"))
end

T["Edit File"]["keeps CRLF line endings when the model sends LF"] = function()
  child.lua([[
    _G.write_raw("local function greet()\r\n  return 'Hello, '\r\nend\r\n")
    _G.run_edit({ old_string = "  return 'Hello, '\nend", new_string = "  return 'Hi, '\nend" })
  ]])
  h.eq("local function greet()\r\n  return 'Hi, '\r\nend\r\n", child.lua_get("_G.read_raw()"))
end

T["Edit File"]["edits a file already loaded in a buffer"] = function()
  child.lua([[
    _G.write_raw("local x = 1\nlocal y = 2\n")
    vim.cmd("edit " .. _G.TEST_FILE)
    _G.run_edit({ old_string = "local x = 1", new_string = "local x = 10" })
  ]])
  h.eq({ "local x = 10", "local y = 2" }, child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  h.eq("local x = 10\nlocal y = 2\n", child.lua_get("_G.read_raw()"))
end

T["Edit File"]["reports a failed match back to the LLM"] = function()
  local output = child.lua([[
    _G.write_raw("local x = 1\n")
    return _G.run_edit({ old_string = "local y = 1", new_string = "local y = 2" })
  ]])
  h.expect_contains("`old_string` was not found", output)
  h.eq("local x = 1\n", child.lua_get("_G.read_raw()"))
end

T["Edit File"]["DOES NOT overwrite a FILE that changed during review"] = function()
  local output = child.lua([[
    local diff = require("codecompanion.interactions.chat.tools.builtin.helpers.diff")
    diff.review = function(opts) _G.pending_review = opts end

    _G.write_raw("local x = 1\n")
    _G.run_edit({ old_string = "local x = 1", new_string = "local x = 2" })
    _G.write_raw("local x = 99\n")
    _G.pending_review.apply()
    vim.wait(10)
    return chat.messages[#chat.messages].content
  ]])
  h.expect_contains("the file changed after the edit was proposed", output)
  h.eq("local x = 99\n", child.lua_get("_G.read_raw()"))
end

T["Edit File"]["DOES NOT overwrite a BUFFER that changed during review"] = function()
  local output = child.lua([[
    local diff = require("codecompanion.interactions.chat.tools.builtin.helpers.diff")
    diff.review = function(opts) _G.pending_review = opts end

    _G.write_raw("local x = 1\n")
    vim.cmd("edit " .. _G.TEST_FILE)
    _G.run_edit({ old_string = "local x = 1", new_string = "local x = 2" })
    vim.api.nvim_buf_set_lines(vim.fn.bufnr(_G.TEST_FILE), 0, -1, false, { "local x = 99" })
    _G.pending_review.apply()
    vim.wait(10)
    return chat.messages[#chat.messages].content
  ]])
  h.expect_contains("the buffer changed after the edit was proposed", output)
  h.eq({ "local x = 99" }, child.lua_get("vim.api.nvim_buf_get_lines(vim.fn.bufnr(_G.TEST_FILE), 0, -1, false)"))
end

T["Edit File"]["fires FileEdited with the first changed line"] = function()
  child.lua([[
    _G.write_raw("before\ntarget\nafter\n")
    _G.file_edits = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionFileEdited",
      callback = function(args)
        table.insert(_G.file_edits, args.data)
      end,
    })
    _G.run_edit({ old_string = "target", new_string = "replacement" })
  ]])
  local edits = child.lua_get("_G.file_edits")
  h.eq(1, #edits)
  h.eq("edit_file", edits[1].tool)
  h.eq(2, edits[1].line)
end

return T
