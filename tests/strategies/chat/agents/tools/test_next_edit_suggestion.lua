local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()
        _G.TEST_FILE_PATH = os.tmpname()
        _G.output = nil

        -- Create a dummy file for the tool to jump to
        vim.fn.writefile({'line 1', 'line 2', 'line 3', 'line 4', 'line 5', 'line 6', 'line 7', 'line 8', 'line 9', 'line 10', 'line 11'}, _G.TEST_FILE_PATH)
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
        pcall(vim.uv.fs_unlink, _G.TEST_FILE_PATH)
      ]])
    end,
    post_once = child.stop,
  },
})

T["next_edit_suggestion tool"] = function()
  child.lua([[
    -- This simulates the LLM calling the tool with specific arguments
    local tool = {
      {
        ["function"] = {
          name = "next_edit_suggestion",
          -- The path to the file you created, and the line number to jump to
          arguments = string.format('{"filepath": "%s", "line": 9}', _G.TEST_FILE_PATH),
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200) -- Give Neovim a moment to process the jump
  ]])

  -- Retrieve the current buffer name and cursor position from the child Neovim instance
  local current_winnr = child.lua_get("vim.api.nvim_get_current_win()")
  local current_bufnr = child.lua_get(string.format("vim.api.nvim_win_get_buf(%d)", current_winnr))
  local current_bufname = child.lua_get(string.format("vim.api.nvim_buf_get_name(%d)", current_bufnr))
  local cursor_pos = child.lua_get(string.format("vim.api.nvim_win_get_cursor(%d)", current_winnr))
  local expected_path = child.lua("return vim.fs.normalize(_G.TEST_FILE_PATH)")

  h.expect_contains(expected_path, current_bufname, "Should jump to the correct file")
  h.eq(10, cursor_pos[1], "Should jump to the correct line")
end

return T
