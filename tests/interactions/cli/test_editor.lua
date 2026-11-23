local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        editor = require("codecompanion.interactions.cli.editor")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Editor"] = new_set()

T["Editor"]["find_reference() reads a line number after a colon"] = function()
  local reference = child.lua([[
    return editor.find_reference({ line = "  Updated lua/codecompanion/init.lua:42 to fix it", col = 15 })
  ]])
  h.eq({ path = "lua/codecompanion/init.lua", line_number = 42 }, reference)
end

T["Editor"]["find_reference() reads a markdown line anchor"] = function()
  local reference = child.lua([[
    return editor.find_reference({ line = "[init.lua](lua/codecompanion/init.lua#L7)", col = 20 })
  ]])
  h.eq({ path = "lua/codecompanion/init.lua", line_number = 7 }, reference)
end

T["Editor"]["find_reference() matches with the cursor ON the line number"] = function()
  local reference = child.lua([[
    local line = "see lua/codecompanion/init.lua:42"
    return editor.find_reference({ line = line, col = #line })
  ]])
  h.eq({ path = "lua/codecompanion/init.lua", line_number = 42 }, reference)
end

T["Editor"]["find_reference() takes the word under the cursor, not the first path"] = function()
  local reference = child.lua([[
    local line = "Edit(lua/a.lua) and Read(lua/b.lua)."
    return editor.find_reference({ line = line, col = line:find("lua/b") })
  ]])
  h.eq({ path = "lua/b.lua" }, reference)
end

T["Editor"]["describe() shares the current file and cursor"] = function()
  local description = child.lua([[
    vim.cmd.edit("lua/codecompanion/init.lua")
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    editor.track()
    return editor.describe()
  ]])
  h.expect_contains("- Current file: lua/codecompanion/init.lua, cursor on line 10", description)
end

T["Editor"]["describe() falls back to another file window once the agent takes over the code window"] = function()
  local description = child.lua([[
    vim.cmd.edit("lua/codecompanion/init.lua")
    vim.cmd.vsplit("README.md")
    editor.track()
    vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))
    return editor.describe()
  ]])
  h.expect_contains("- Current file: lua/codecompanion/init.lua", description)
end

T["Editor"]["describe() shares a selection with the FIRST prompt only"] = function()
  local descriptions = child.lua([[
    vim.cmd.edit("lua/codecompanion/init.lua")
    editor.track()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd("normal! Vj")
    vim.cmd("normal! \27")
    vim.wait(100)
    return { first = editor.describe(), second = editor.describe() }
  ]])
  h.expect_contains("- Selected: lua/codecompanion/init.lua, lines 3-4", descriptions.first)
  h.eq(nil, descriptions.second:find("Selected", 1, true))
end

T["Editor"]["open_file() uses the code window, NOT the agent's"] = function()
  local result = child.lua([[
    vim.cmd.edit("README.md")
    local code_winnr = vim.api.nvim_get_current_win()
    editor.track()

    vim.cmd.vsplit()
    local agent_winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(agent_winnr, vim.api.nvim_create_buf(false, true))

    editor.open_file({ path = "lua/codecompanion/init.lua", line_number = 5, from_winnr = agent_winnr })
    return {
      in_code_window = vim.api.nvim_get_current_win() == code_winnr,
      file = vim.fn.expand("%"),
      line = vim.api.nvim_win_get_cursor(0)[1],
      agent_untouched = vim.bo[vim.api.nvim_win_get_buf(agent_winnr)].buftype == "nofile",
    }
  ]])
  h.eq({ in_code_window = true, file = "lua/codecompanion/init.lua", line = 5, agent_untouched = true }, result)
end

return T
