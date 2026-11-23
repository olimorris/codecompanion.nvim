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

T["Editor"]["find_reference() keeps the spaces in a path in backticks"] = function()
  local reference = child.lua([[
    local line = "Created `docs/my notes.md:4` for you"
    return editor.find_reference({ line = line, col = line:find("notes") })
  ]])
  h.eq({ path = "docs/my notes.md", line_number = 4 }, reference)
end

T["Editor"]["find_reference() takes the path under the cursor from a command in backticks"] = function()
  local reference = child.lua([[
    local line = "Run `git diff lua/codecompanion/init.lua` to see it"
    return editor.find_reference({ line = line, col = line:find("init") })
  ]])
  h.eq({ path = "lua/codecompanion/init.lua" }, reference)
end

T["Editor"]["find_reference() keeps non-ASCII characters and a Windows drive"] = function()
  local references = child.lua([[
    return {
      editor.find_reference({ line = "see docs/café.md:2", col = 8 }),
      editor.find_reference({ line = "see C:\\src\\main.lua:3", col = 10 }),
    }
  ]])
  h.eq({ { path = "docs/café.md", line_number = 2 }, { path = "C:\\src\\main.lua", line_number = 3 } }, references)
end

T["Editor"]["find_reference() takes the word under the cursor, not the first path"] = function()
  local reference = child.lua([[
    local line = "Edit(lua/a.lua) and Read(lua/b.lua)."
    return editor.find_reference({ line = line, col = line:find("lua/b") })
  ]])
  h.eq({ path = "lua/b.lua" }, reference)
end

T["Editor"]["find_reference_at() rejoins a path the agent wrapped onto the next line"] = function()
  local reference = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "Updated lua/codecompanion/inter",
      "  actions/cli/init.lua:5 to fix it",
    })
    return editor.find_reference_at({ bufnr = bufnr, row = 2, col = 6 })
  ]])
  h.eq({ path = "lua/codecompanion/interactions/cli/init.lua", line_number = 5 }, reference)
end

T["Editor"]["find_reference_at() DOES NOT join a path that fits on its line"] = function()
  local reference = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "Read lua/codecompanion/init.lua",
      "lua/codecompanion/config.lua",
    })
    return editor.find_reference_at({ bufnr = bufnr, row = 1, col = 10 })
  ]])
  h.eq({ path = "lua/codecompanion/init.lua" }, reference)
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

T["Editor"]["open_file() uses the user's split EVEN when it holds an unnamed buffer"] = function()
  local result = child.lua([[
    local user_winnr = vim.api.nvim_get_current_win()
    vim.cmd.vsplit()
    local agent_winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(agent_winnr, vim.api.nvim_create_buf(false, true))
    editor.track()

    editor.open_file({ path = "lua/codecompanion/init.lua", from_winnr = agent_winnr })
    return { in_user_window = vim.api.nvim_get_current_win() == user_winnr, windows = #vim.api.nvim_list_wins() }
  ]])
  h.eq({ in_user_window = true, windows = 2 }, result)
end

return T
