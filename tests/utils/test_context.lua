local h = require("tests.helpers")

local test_text = {
  "first line with leading spaces",
  "second line of text here",
  "third line goes here",
  "fourth line ends here",
}

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua(string.format(
        [[
        _G.test_buffer = ""
        _G.context = require("codecompanion.utils.context")
        _G.test_text = %s
        _G.test_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(_G.test_buffer, 0, -1, false, _G.test_text)
        vim.api.nvim_set_current_buf(_G.test_buffer)
        vim.opt.showmode = false

        -- Ensure we're in normal mode and selection is inclusive
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
        vim.o.selection = "inclusive"
      ]],
        vim.inspect(test_text)
      ))
    end,
    post_case = function()
      child.lua([[
        vim.api.nvim_buf_delete(_G.test_buffer, { force = true })
      ]])
    end,
    post_once = child.stop,
  },
})
T["Utils->Context"] = new_set()

T["Utils->Context"]["can handle commands through keymaps"] = function()
  local result = child.lua([[
    _G.command_result = nil

    vim.api.nvim_create_user_command("TestVisualSelection", function()
      local lines = _G.context.get_visual_selection(_G.test_buffer)
      _G.command_result = lines
    end, { range = true })

    vim.keymap.set("v", "<Leader>ts", "<cmd>TestVisualSelection<CR>", { buffer = _G.test_buffer })

    vim.cmd("normal! gg0Vj") -- Select 2 lines
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Leader>ts", true, false, true), "x", true)
    vim.cmd("redraw")

    return _G.command_result
  ]])

  h.not_eq(nil, result)
  h.eq(2, #result)
  h.eq(test_text[1], result[1])
  h.eq(test_text[2], result[2])
end

T["Utils->Context"]["should get full lines when using line-wise visual mode"] = function()
  local lines = child.lua([[
    vim.cmd("normal! gg0wV") -- Move to first word and enter line-wise visual
    return _G.context.get_visual_selection(_G.test_buffer)
  ]])
  h.eq(test_text[1], lines[1])
end

T["Utils->Context"]["should handle multi line selection"] = function()
  local ctx = child.lua([[
      vim.cmd("normal! gg0V2j") -- Select first 3 lines
      local ctx = _G.context.get(_G.test_buffer)
      return ctx
  ]])

  h.eq(true, ctx.is_visual)
  h.eq(3, #ctx.lines)
  h.eq(test_text[1], ctx.lines[1])
  h.eq(test_text[2], ctx.lines[2])
  h.eq(test_text[3], ctx.lines[3])
end

T["Utils->Context"]["should handle character-wise visual selection"] = function()
  local lines = child.lua([[
      vim.cmd("normal! gg0wvej") -- Move to first word, visual select, next word, down
      return _G.context.get_visual_selection(_G.test_buffer)
  ]])

  h.eq(2, #lines)
  h.eq(true, lines[1]:find("line with leading spaces") ~= nil)
  h.eq(true, lines[2]:find("second lin") ~= nil)
  -- Or for exact matching (really shouldn't be needed, but why not):
  h.eq({
    "line with leading spaces",
    "second lin",
  }, lines)
end

T["Utils->Context"]["should handle switching between visual modes"] = function()
  local lines = child.lua([[
    vim.cmd("normal! gg0wvej") -- Select some text and extend to next line
    vim.cmd("normal! V") -- Switch to line-wise
    return _G.context.get_visual_selection(_G.test_buffer)
  ]])

  h.eq(test_text[1], lines[1])
  h.eq(test_text[2], lines[2])
end

T["Utils->Context"]["should handle single-line partial selection"] = function()
  local lines = child.lua([[
    vim.cmd("normal! gg0v2e") -- Select two words
    return _G.context.get_visual_selection(_G.test_buffer)
  ]])

  h.eq(1, #lines)
  h.eq(true, lines[1]:find("first line") ~= nil)
end

T["Utils->Context"]["should handle reverse selection (end before start)"] = function()
  local lines = child.lua([[
    vim.cmd("normal! gg$v0") -- Select line backwards
    return _G.context.get_visual_selection(_G.test_buffer)
  ]])

  h.eq(1, #lines)
  h.eq(test_text[1], lines[1])
end

T["Utils->Context"]["should get whole buffer when there's no visual selection"] = function()
  local lines = child.lua([[
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
    return _G.context.get_visual_selection(_G.test_buffer)
  ]])

  h.eq(#test_text, #lines)
  for i = 1, #test_text do
    h.eq(test_text[i], lines[i])
  end
end

T["Utils->Context"]["should handle context retrieval in normal mode"] = function()
  local ctx = child.lua([[
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
    return _G.context.get(_G.test_buffer)
  ]])

  h.eq(false, ctx.is_visual)
  h.eq(true, ctx.is_normal)
  h.eq("n", ctx.mode)
  -- Check if cursor position is being tracked
  h.eq({ 1, 0 }, ctx.cursor_pos)
end

T["Utils->Context"]["should handle bottom-to-top line-wise visual selection"] = function()
  local lines = child.lua([[
    vim.cmd("normal! GV2k") -- Select 3 lines upward
    return _G.context.get_visual_selection(_G.test_buffer)
  ]])

  h.eq(3, #lines)
  local start_idx = #test_text - 2
  for i = 1, 3 do
    h.eq(test_text[start_idx + i - 1], lines[i])
  end
end

T["Utils->Context"]["should clear previous visual selection"] = function()
  local ctx = child.lua([[
    -- Make a visual selection first
    vim.cmd("normal! ggV2j")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
    return _G.context.get(_G.test_buffer)
  ]])

  h.eq(false, ctx.is_visual)
  h.eq(true, ctx.is_normal)
  h.eq(0, #ctx.lines) -- Check that lines are empty in normal mode
end

T["Utils->Context"]["should handle current buffer when no buffer specified"] = function()
  local ctx = child.lua([[
    return _G.context.get()
  ]])
  local buf = child.lua([[
    return vim.api.nvim_get_current_buf()
  ]])

  h.eq(buf, ctx.bufnr)
end

return T
