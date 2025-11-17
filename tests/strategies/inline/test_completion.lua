local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      if vim.fn.has("nvim-0.12") == 0 then
        return
      end

      h.child_start(child)
      -- Set up a buffer with some content
      child.o.lines = 20
      child.o.columns = 80
      child.bo.readonly = false

      -- Load the completion module and set up mocking
      child.lua([[
        -- Mock vim.lsp.inline_completion.get before loading the module
        _G.mock_get_called = false
        _G.mock_get_opts = nil
        _G.original_get = vim.lsp.inline_completion.get

        vim.lsp.inline_completion.get = function(opts)
          _G.mock_get_called = true
          _G.mock_get_opts = opts

          -- The mock will be set per-test
          if _G.mock_completion_item and opts.on_accept then
            opts.on_accept(_G.mock_completion_item)
          end
        end

        -- Now load the module
        _G.completion = require("codecompanion.strategies.inline.completion")
      ]])
    end,
    post_case = function()
      if vim.fn.has("nvim-0.12") == 0 then
        return
      end

      child.lua([[
        vim.lsp.inline_completion.get = _G.original_get
        _G.mock_completion_item = nil
        _G.mock_get_called = false
        _G.mock_get_opts = nil
      ]])
    end,
    post_once = child.stop,
  },
})

---Helper to set buffer with cursor marker and enter insert mode
---Accepts string "text|" or table {"line1", "line|2"} where | marks cursor position
---@param text string|table
local function set_buffer_text(text)
  if type(text) == "string" then
    local cursor_pos = text:find("|", 1, true)
    if not cursor_pos then
      error("No cursor marker '|' found in text")
    end

    local line = text:sub(1, cursor_pos - 1) .. text:sub(cursor_pos + 1)
    child.api.nvim_buf_set_lines(0, 0, -1, true, { line })
    child.cmd("startinsert!")
    child.api.nvim_win_set_cursor(0, { 1, cursor_pos - 1 })
  elseif type(text) == "table" then
    local cursor_row, cursor_col
    local lines = {}

    for i, line in ipairs(text) do
      local pos = line:find("|", 1, true)
      if pos then
        cursor_row = i
        cursor_col = pos - 1
        table.insert(lines, line:sub(1, pos - 1) .. line:sub(pos + 1))
      else
        table.insert(lines, line)
      end
    end

    if not cursor_row then
      error("No cursor marker '|' found in text")
    end

    child.api.nvim_buf_set_lines(0, 0, -1, true, lines)
    child.cmd("startinsert!")
    child.api.nvim_win_set_cursor(0, { cursor_row, cursor_col })
  else
    error("Expected string or table")
  end
end

T["accept_word()"] = new_set()

T["accept_word()"]["works with simple word completion"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("-- Create a fib|")

  -- Set up the mock completion
  child.lua([[
    _G.mock_completion_item = {
      insert_text = "-- Create a fibonacci sequence",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 15 }
      }
    }

    -- Accept a word
    _G.completion.accept_word()
  ]])

  -- Verify: should have added "onacci " (7 chars) from "fibonacci sequence"
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "-- Create a fibonacci " })
  h.eq(child.api.nvim_win_get_cursor(0), { 1, 22 }) -- 15 + 7 = 22
end

T["accept_word()"]["works with punctuation in completion"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("local x|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "local x = require('foo')",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 7 }
      }
    }

    _G.completion.accept_word()
  ]])

  -- Should insert " = " (whitespace + punctuation + whitespace)
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "local x = " })
end

T["accept_word()"]["works with newline in word"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("function test()|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "function test()\n  return 42\nend",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 15 }
      }
    }

    _G.completion.accept_word()
  ]])

  -- The pattern will match "\n  return " as the first "word" (newline + whitespace + word + whitespace)
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "function test()", "  return " })
  h.eq(child.api.nvim_win_get_cursor(0), { 2, 9 })
end

T["accept_word()"]["ignores stale completion (cursor before range end)"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("test some |long text here")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "test completion",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 4 }  -- Range ends at 4, but cursor is at 10
      }
    }

    _G.completion.accept_word()
  ]])

  -- Buffer should be unchanged
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "test some long text here" })
end

T["accept_word()"]["handles empty buffer"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "hello world",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 0 }
      }
    }

    _G.completion.accept_word()
  ]])

  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "hello " })
  h.eq(child.api.nvim_win_get_cursor(0), { 1, 6 })
end

T["accept_word()"]["handles auto-pairs with cursor inside brackets"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("local function hello_world(|)")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "local function hello_world(arg)",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 27 }
      }
    }

    _G.completion.accept_word()
  ]])

  -- Should insert "arg" without being confused by the trailing ")"
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "local function hello_world(arg)" })
  h.eq(child.api.nvim_win_get_cursor(0), { 1, 30 })
end

T["accept_word()"]["handles auto-pairs with cursor inside quotes"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text('print("|")') -- print("|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "print(\"hello world\")",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 7 }
      }
    }

    _G.completion.accept_word()
  ]])

  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { 'print("hello ")' })
  h.eq(child.api.nvim_win_get_cursor(0), { 1, 13 })
end

T["accept_word()"]["handles completion that doesn't start with existing text"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("foo bar|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "completely different",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 7 }
      }
    }

    _G.completion.accept_word()
  ]])

  -- Should still extract a word from the full suggestion
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "foo barcompletely " })
end

T["accept_line()"] = new_set()

T["accept_line()"]["works with single line completion"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("-- Comment|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "-- Comment about the code",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 10 }
      }
    }

    _G.completion.accept_line()
  ]])

  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "-- Comment about the code" })
  h.eq(child.api.nvim_win_get_cursor(0), { 1, 25 })
end

T["accept_line()"]["works with multi-line completion"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("function test()|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "function test()\n  return 42\nend",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 15 }
      }
    }

    _G.completion.accept_line()
  ]])

  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "function test()", "  return 42", "" })
  h.eq(child.api.nvim_win_get_cursor(0), { 3, 0 })
end

T["accept_line()"]["ignores stale completion"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("test some |long text here")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "test line",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 4 }
      }
    }

    _G.completion.accept_line()
  ]])

  -- Buffer should be unchanged
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "test some long text here" })
end

T["accept_line()"]["handles completion without newline"] = function()
  if vim.fn.has("nvim-0.12") == 0 then
    MiniTest.skip("Requires Neovim 0.12+ for vim.lsp.inline_completion")
  end

  set_buffer_text("hello|")

  child.lua([[
    _G.mock_completion_item = {
      insert_text = "hello world",
      range = {
        start = { row = 0, col = 0 },
        end_ = { row = 0, col = 5 }
      }
    }

    _G.completion.accept_line()
  ]])

  -- Should insert the entire remaining text (no newline to stop at)
  h.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { "hello world" })
  h.eq(child.api.nvim_win_get_cursor(0), { 1, 11 })
end

return T
