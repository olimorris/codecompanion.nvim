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
    it("should get full lines when using line-wise visual mode", function()
      -- Move to middle of first line and make line-wise selection
      vim.cmd("normal! gg0wV") -- Move to first word and enter line-wise visual
      local lines = context.get_visual_selection(test_buffer)
      -- print("Line-wise selection content:", vim.inspect(lines))
      assert.are.same(test_text[1], lines[1])
    end)

    it("should handle selection via keymap", function()
      -- Simulate visual selection of multiple lines
      vim.cmd("normal! gg0V2j") -- Select first 3 lines
      local ctx = context.get(test_buffer)
      -- print("Keymap selection content:", vim.inspect(ctx.lines))
      assert.equals(true, ctx.is_visual)
      assert.equals(3, #ctx.lines)
      assert.are.same(test_text[1], ctx.lines[1])
      assert.are.same(test_text[2], ctx.lines[2])
      assert.are.same(test_text[3], ctx.lines[3])
    end)

    it("should handle character-wise visual selection", function()
      -- Select from "line" in first line to "lin" in second line
      vim.cmd("normal! gg0wvej") -- Move to first word, visual select, next word, down
      local lines = context.get_visual_selection(test_buffer)
      -- print("Char-wise selection content:", vim.inspect(lines))
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
      -- Start with char-wise and switch to line-wise
      vim.cmd("normal! gg0wvej") -- Select some text and extend to next line
      vim.cmd("normal! V") -- Switch to line-wise
      local lines = context.get_visual_selection(test_buffer)
      -- print("Mode switching content:", vim.inspect(lines))
      assert.are.same(test_text[1], lines[1])
      assert.are.same(test_text[2], lines[2])
    end)

    it("should handle single-line partial selection", function()
      vim.cmd("normal! gg0v2e") -- Select two words
      local lines = context.get_visual_selection(test_buffer)
      -- print("Partial selection content:", vim.inspect(lines))
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("first line"))
    end)

    it("should handle reverse selection (end before start)", function()
      vim.cmd("normal! gg$v0") -- Select line backwards
      local lines = context.get_visual_selection(test_buffer)
      -- print("Reverse selection content:", vim.inspect(lines))
      assert.equals(1, #lines)
      assert.are.same(test_text[1], lines[1])
    end)

    it("should handle current buffer when no buffer specified", function()
      local ctx = context.get()
      assert.equals(vim.api.nvim_get_current_buf(), ctx.bufnr)
    end)
  end)
end)
