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

        _G.run_overwrite = function(args)
          args.filepath = args.filepath or _G.TEST_FILE
          tools:execute(chat, { { ["function"] = { name = "overwrite_file", arguments = vim.json.encode(args) } } })
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

T["Overwrite File"] = new_set()

T["Overwrite File"]["overwrites a file"] = function()
  child.lua([[
    _G.write_raw("local x = 1\nlocal y = 2\n")
    _G.run_overwrite({ content = "return {}\n" })
  ]])
  h.eq("return {}\n", child.lua_get("_G.read_raw()"))
end

T["Overwrite File"]["DOES NOT create a file that DOES NOT exist"] = function()
  local output = child.lua([[
    return _G.run_overwrite({ content = "return {}\n" })
  ]])
  h.expect_contains("does not exist", output)
  h.eq(false, child.lua_get("vim.uv.fs_stat(_G.TEST_FILE) ~= nil"))
end

T["Overwrite File"]["keeps CRLF line endings when the model sends LF"] = function()
  child.lua([[
    _G.write_raw("local x = 1\r\nlocal y = 2\r\n")
    _G.run_overwrite({ content = "local x = 10\nlocal y = 20\n" })
  ]])
  h.eq("local x = 10\r\nlocal y = 20\r\n", child.lua_get("_G.read_raw()"))
end

T["Overwrite File"]["overwrites a file loaded in a buffer WITHOUT adding a blank last line"] = function()
  child.lua([[
    _G.write_raw("local x = 1\nlocal y = 2\n")
    vim.cmd("edit " .. _G.TEST_FILE)
    _G.run_overwrite({ content = "return {}\n" })
  ]])
  h.eq({ "return {}" }, child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  h.eq("return {}\n", child.lua_get("_G.read_raw()"))
end

T["Overwrite File"]["DOES NOT overwrite a file that changed during review"] = function()
  local output = child.lua([[
    local diff = require("codecompanion.interactions.chat.tools.builtin.helpers.diff")
    diff.review = function(opts) _G.pending_review = opts end

    _G.write_raw("local x = 1\n")
    _G.run_overwrite({ content = "return {}\n" })
    _G.write_raw("local x = 99\n")
    _G.pending_review.apply()
    vim.wait(10)
    return chat.messages[#chat.messages].content
  ]])
  h.expect_contains("Could not overwrite", output)
  h.eq("local x = 99\n", child.lua_get("_G.read_raw()"))
end

T["Overwrite File"]["fires FileEdited with the first changed line"] = function()
  child.lua([[
    _G.write_raw("before\ntarget\nafter\n")
    _G.file_edits = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionFileEdited",
      callback = function(args)
        table.insert(_G.file_edits, args.data)
      end,
    })
    _G.run_overwrite({ content = "before\nreplacement\nafter\n" })
  ]])
  local edits = child.lua_get("_G.file_edits")
  h.eq(1, #edits)
  h.eq("overwrite_file", edits[1].tool)
  h.eq(2, edits[1].line)
end

return T
