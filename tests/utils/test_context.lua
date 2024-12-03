local context = require("codecompanion.utils.context")
local h = require("tests.helpers")

describe("context visual selection", function()
  local test_buffer
  local test_text = {
    "first line with leading spaces",
    "second line of text here",
    "third line goes here",
    "fourth line ends here",
  }

  before_each(function()
    test_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, test_text)
    vim.api.nvim_set_current_buf(test_buffer)
    vim.opt.showmode = false
    -- Ensure we're in normal mode and selection is inclusive
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
    vim.o.selection = "inclusive"
  end)

  after_each(function()
    vim.api.nvim_buf_delete(test_buffer, { force = true })
  end)

  describe("cursor & visual selection", function()
    it("should handle command through keymap", function()
      local command_result = nil

      vim.api.nvim_create_user_command("TestVisualSelection", function()
        local lines = context.get_visual_selection(test_buffer)
        command_result = lines
      end, { range = true })

      vim.keymap.set("v", "<Leader>ts", "<cmd>TestVisualSelection<CR>", { buffer = test_buffer })

      vim.cmd("normal! gg0Vj") -- Select 2 lines
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Leader>ts", true, false, true), "x", true)
      vim.cmd("redraw")

      h.not_eq(nil, command_result)
      h.eq(2, #command_result)
      h.eq(test_text[1], command_result[1])
      h.eq(test_text[2], command_result[2])
      -- Clean up
      vim.api.nvim_del_user_command("TestVisualSelection")
      vim.keymap.del("v", "<Leader>ts", { buffer = test_buffer })
    end)

    it("should get full lines when using line-wise visual mode", function()
      vim.cmd("normal! gg0wV") -- Move to first word and enter line-wise visual
      local lines = context.get_visual_selection(test_buffer)
      h.eq(test_text[1], lines[1])
    end)

    it("should handle multiline selection", function()
      vim.cmd("normal! gg0V2j") -- Select first 3 lines
      local ctx = context.get(test_buffer)
      h.eq(true, ctx.is_visual)
      h.eq(3, #ctx.lines)
      h.eq(test_text[1], ctx.lines[1])
      h.eq(test_text[2], ctx.lines[2])
      h.eq(test_text[3], ctx.lines[3])
    end)

    it("should handle character-wise visual selection", function()
      vim.cmd("normal! gg0wvej") -- Move to first word, visual select, next word, down
      local lines = context.get_visual_selection(test_buffer)
      h.eq(2, #lines)
      h.eq(true, lines[1]:find("line with leading spaces") ~= nil)
      h.eq(true, lines[2]:find("second lin") ~= nil)
      -- Or for exact matching (really shouldn't be needed, but why not):
      h.eq({
        "line with leading spaces",
        "second lin",
      }, lines)
    end)

    it("should handle switching between visual modes", function()
      vim.cmd("normal! gg0wvej") -- Select some text and extend to next line
      vim.cmd("normal! V") -- Switch to line-wise
      local lines = context.get_visual_selection(test_buffer)
      h.eq(test_text[1], lines[1])
      h.eq(test_text[2], lines[2])
    end)

    it("should handle single-line partial selection", function()
      vim.cmd("normal! gg0v2e") -- Select two words
      local lines = context.get_visual_selection(test_buffer)
      h.eq(1, #lines)
      h.eq(true, lines[1]:find("first line") ~= nil)
    end)

    it("should handle reverse selection (end before start)", function()
      vim.cmd("normal! gg$v0") -- Select line backwards
      local lines = context.get_visual_selection(test_buffer)
      h.eq(1, #lines)
      h.eq(test_text[1], lines[1])
    end)

    it("should get whole buffer when there's no visual selection", function()
      -- Ensure we're in normal mode with no previous visual selection
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
      local lines = context.get_visual_selection(test_buffer)
      h.eq(#test_text, #lines)
      for i = 1, #test_text do
        h.eq(test_text[i], lines[i])
      end
    end)

    it("should handle context retrieval in normal mode", function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
      local ctx = context.get(test_buffer)
      h.eq(false, ctx.is_visual)
      h.eq(true, ctx.is_normal)
      h.eq("n", ctx.mode)
      -- Check if cursor position is being tracked
      h.eq({ 1, 0 }, ctx.cursor_pos)
    end)

    it("should handle bottom-to-top line-wise visual selection", function()
      vim.cmd("normal! GV2k") -- Select 3 lines upward
      local lines = context.get_visual_selection(test_buffer)
      h.eq(3, #lines)
      local start_idx = #test_text - 2
      for i = 1, 3 do
        h.eq(test_text[start_idx + i - 1], lines[i])
      end
    end)

    it("should clear previous visual selection", function()
      -- Make a visual selection first
      vim.cmd("normal! ggV2j")
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "nx", true)
      local ctx = context.get(test_buffer)
      h.eq(false, ctx.is_visual)
      h.eq(true, ctx.is_normal)
      h.eq(0, #ctx.lines) -- Check that lines are empty in normal mode
    end)

    it("should handle current buffer when no buffer specified", function()
      local ctx = context.get()
      h.eq(vim.api.nvim_get_current_buf(), ctx.bufnr)
    end)
  end)
end)
