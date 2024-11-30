local assert = require("luassert")
local context = require("codecompanion.utils.context")

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
    -- Ensure we're in normal mode and selection is inclusive
    vim.cmd("normal! \27") -- ESC
    vim.o.selection = "inclusive"
  end)

  after_each(function()
    vim.api.nvim_buf_delete(test_buffer, { force = true })
  end)

  describe("cursor & visual selection", function()
    it("should handle command through keymap", function()
      local command_result = nil

      vim.api.nvim_create_user_command("TestVisualSelection", function(args)
        local lines = context.get_visual_selection(test_buffer)
        command_result = lines
      end, { range = true })

      vim.keymap.set("v", "<Leader>ts", "<cmd>TestVisualSelection<CR>", { buffer = test_buffer })

      vim.cmd("normal! gg0Vj") -- Select 2 lines
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Leader>ts", true, false, true), "x", true)
      vim.cmd("redraw")

      assert.is_not_nil(command_result)
      assert.equals(2, #command_result)
      assert.are.same(test_text[1], command_result[1])
      assert.are.same(test_text[2], command_result[2])
      -- Clean up
      vim.api.nvim_del_user_command("TestVisualSelection")
      vim.keymap.del("v", "<Leader>ts", { buffer = test_buffer })
    end)

    it("should get full lines when using line-wise visual mode", function()
      vim.cmd("normal! gg0wV") -- Move to first word and enter line-wise visual
      local lines = context.get_visual_selection(test_buffer)
      assert.are.same(test_text[1], lines[1])
    end)

    it("should handle multiline selection", function()
      vim.cmd("normal! gg0V2j") -- Select first 3 lines
      local ctx = context.get(test_buffer)
      assert.equals(true, ctx.is_visual)
      assert.equals(3, #ctx.lines)
      assert.are.same(test_text[1], ctx.lines[1])
      assert.are.same(test_text[2], ctx.lines[2])
      assert.are.same(test_text[3], ctx.lines[3])
    end)

    it("should handle character-wise visual selection", function()
      vim.cmd("normal! gg0wvej") -- Move to first word, visual select, next word, down
      local lines = context.get_visual_selection(test_buffer)
      assert.equals(2, #lines)
      assert.truthy(lines[1]:find("line with leading spaces"))
      assert.truthy(lines[2]:find("second lin"))
      -- Or for exact matching (really shouldn't be needed, but why not):
      assert.are.same({
        "line with leading spaces",
        "second lin",
      }, lines)
    end)

    it("should handle switching between visual modes", function()
      vim.cmd("normal! gg0wvej") -- Select some text and extend to next line
      vim.cmd("normal! V") -- Switch to line-wise
      local lines = context.get_visual_selection(test_buffer)
      assert.are.same(test_text[1], lines[1])
      assert.are.same(test_text[2], lines[2])
    end)

    it("should handle single-line partial selection", function()
      vim.cmd("normal! gg0v2e") -- Select two words
      local lines = context.get_visual_selection(test_buffer)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("first line"))
    end)

    it("should handle reverse selection (end before start)", function()
      vim.cmd("normal! gg$v0") -- Select line backwards
      local lines = context.get_visual_selection(test_buffer)
      assert.equals(1, #lines)
      assert.are.same(test_text[1], lines[1])
    end)

    it("should get whole buffer when there's no visual selection", function()
      -- Ensure we're in normal mode with no previous visual selection
      vim.cmd("normal! \27") -- ESC
      local lines = context.get_visual_selection(test_buffer)
      assert.equals(#test_text, #lines)
      for i = 1, #test_text do
        assert.are.same(test_text[i], lines[i])
      end
    end)

    it("should handle context retrieval in normal mode", function()
      vim.cmd("normal! \27")
      local ctx = context.get(test_buffer)
      assert.equals(false, ctx.is_visual)
      assert.equals(true, ctx.is_normal)
      assert.equals("n", ctx.mode)
      -- Check if cursor position is being tracked
      assert.are.same({ 1, 0 }, ctx.cursor_pos)
    end)

    it("should handle bottom-to-top line-wise visual selection", function()
      vim.cmd("normal! GV3k") -- Select 3 lines upward
      local lines = context.get_visual_selection(test_buffer)
      assert.equals(4, #lines)
      for i = 1, 4 do
        assert.are.same(test_text[i], lines[i])
      end
    end)

    it("should clear previous visual selection", function()
      -- Make a visual selection first
      vim.cmd("normal! ggV2j")
      vim.cmd("normal! \27") -- Exit visual mode
      -- Wait a moment to ensure mode change is processed
      vim.cmd("sleep 10m")
      -- Now get context in normal mode
      local ctx = context.get(test_buffer)
      assert.equals(false, ctx.is_visual)
      assert.equals(true, ctx.is_normal)
      assert.equals(0, #ctx.lines)
    end)

    it("should handle current buffer when no buffer specified", function()
      local ctx = context.get()
      assert.equals(vim.api.nvim_get_current_buf(), ctx.bufnr)
    end)
  end)
end)
