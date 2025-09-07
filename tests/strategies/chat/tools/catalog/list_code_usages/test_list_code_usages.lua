-- tests/strategies/chat/tools/catalog/list_code_usages/test_integration_grep.lua
local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Load modules under test
        ListCodeUsagesTool = require("codecompanion.strategies.chat.tools.catalog.list_code_usages")
        ResultProcessor = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.result_processor")
        SymbolFinder = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.symbol_finder")
        LspHandler = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.lsp_handler")

        -- Test workspace setup
        local tmp_root = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.tempname(), ":h"))
        _G.TEST_WS = vim.fs.joinpath(tmp_root, "cc_list_code_usages_ws")
        vim.fn.mkdir(_G.TEST_WS, "p")
        vim.cmd("cd " .. vim.fn.fnameescape(_G.TEST_WS))

        -- Create minimal source files (Lua) to trigger grep + fallback extraction
        local function writef(rel, lines)
          local p = vim.fs.joinpath(_G.TEST_WS, rel)
          vim.fn.mkdir(vim.fs.dirname(p), "p")
          vim.fn.writefile(lines, p)
          return p
        end

        _G.FILE_A = writef("src/a.lua", {
          "local function foo(x)",
          "  return x + 1",
          "end",
          "",
          "local function bar()",
          "  return foo(41)",
          "end",
        })

        _G.FILE_B = writef("src/b.lua", {
          "local function baz()",
          "  local y = foo(10)",
          "  return y",
          "end",
        })

        -- Open a context window on FILE_A (buffer_context)
        vim.cmd("edit " .. vim.fn.fnameescape(_G.FILE_A))
        local ctx_win = vim.api.nvim_get_current_win()
        local ctx_buf = vim.api.nvim_get_current_buf()

        -- Create a second window to represent the chat window
        vim.cmd("vsplit")
        local chat_win = vim.api.nvim_get_current_win()
        local chat_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(chat_win, chat_buf)

        -- Minimal chat/tools harness
        _G.captured_tool_output = nil
        local chat = {
          buffer_context = { winnr = ctx_win, bufnr = ctx_buf },
          add_tool_output = function(self, tool, content)
            _G.captured_tool_output = content
            return content
          end,
        }
        _G.tools = { chat = chat }

        -- Helpers to build a qflist for foo occurrences
        local function load_buf(path)
          vim.cmd("edit " .. vim.fn.fnameescape(path))
          return vim.api.nvim_get_current_buf()
        end
        local bufa = load_buf(_G.FILE_A)
        local bufb = load_buf(_G.FILE_B)

        -- Compute rough columns for 'foo' (fallback extractor does not require exact)
        local function col_of(s, pat) return (s:find(pat, 1, true) or 1) end

        local a_lines = vim.api.nvim_buf_get_lines(bufa, 0, -1, false)
        local b_lines = vim.api.nvim_buf_get_lines(bufb, 0, -1, false)

        local qf = {
          -- definition in FILE_A line 1
          { bufnr = bufa, lnum = 1, col = col_of(a_lines[1] or "", "foo") },
          -- usage in FILE_A line 6
          { bufnr = bufa, lnum = 6, col = col_of(a_lines[6] or "", "foo") },
          -- usage in FILE_B line 2
          { bufnr = bufb, lnum = 2, col = col_of(b_lines[2] or "", "foo") },
        }
        vim.fn.setqflist(qf)

        -- Stub SymbolFinder to avoid shell grep and control inputs.
        SymbolFinder.find_with_lsp_async = function(symbol, file_paths, cb)
          cb({}) -- No LSP symbols in this integration
        end

        SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb)
          -- Provide "first match" plus full quickfix; tool will also later read getqflist()
          local first = qf[1]
          cb({
            file = vim.fn.bufname(first.bufnr),
            line = first.lnum,
            col = first.col,
            bufnr = first.bufnr,
            qflist = qf,
          })
        end

        -- Stub LSP requests to no-op so only grep path is exercised.
        LspHandler.execute_request_async = function(bufnr, method, cb)
          cb({})
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        if _G.TEST_WS then vim.fn.delete(_G.TEST_WS, "rf") end
        _G.captured_tool_output = nil
        _G.tools = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["validates symbol name is required"] = function()
  child.lua([[
    local tool_context = { args = { symbol_name = "" }, chat = _G.tools.chat }
    local done, res = false, nil
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function(r)
      res = r; done = true
    end)
    vim.wait(300, function() return done end, 10)
    _G.test_result = res
  ]])
  local res = child.lua_get("_G.test_result")
  h.eq("error", res.status)
  h.expect_contains("Symbol name is required", res.data)
end

T["validates symbol name is not nil"] = function()
  child.lua([[
    local tool_context = { args = {}, chat = _G.tools.chat }
    local done, res = false, nil
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function(r)
      res = r; done = true
    end)
    vim.wait(300, function() return done end, 10)
    _G.test_result = res
  ]])
  local res = child.lua_get("_G.test_result")
  h.eq("error", res.status)
  h.expect_contains("Symbol name is required", res.data)
end

T["passes file paths to symbol finder"] = function()
  child.lua([[
    local seen = { lsp = nil, grep = nil }
    local orig_lsp, orig_grep = SymbolFinder.find_with_lsp_async, SymbolFinder.find_with_grep_async

    SymbolFinder.find_with_lsp_async = function(symbol, file_paths, cb)
      seen.lsp = file_paths; cb({})
    end
    SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb)
      seen.grep = file_paths; cb(nil)
    end

    local tool_context = {
      args = { symbol_name = "foo", file_paths = { "src/a.lua", "src/b.lua" } },
      chat = _G.tools.chat,
    }
    local done = false
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function() done = true end)
    vim.wait(400, function() return done end, 10)

    SymbolFinder.find_with_lsp_async, SymbolFinder.find_with_grep_async = orig_lsp, orig_grep
    _G.test_result = seen
  ]])
  local res = child.lua_get("_G.test_result")
  h.not_eq(nil, res.lsp)
  h.not_eq(nil, res.grep)
  h.expect_tbl_contains("src/a.lua", res.lsp)
  h.expect_tbl_contains("src/b.lua", res.lsp)
  h.expect_tbl_contains("src/a.lua", res.grep)
  h.expect_tbl_contains("src/b.lua", res.grep)
end

T["error handler formats error correctly"] = function()
  child.lua([[
    _G.captured_tool_output = nil
    local tool_context = { args = { symbol_name = "foo" }, chat = _G.tools.chat }
    local mock_tools = { chat = _G.tools.chat }
    local stderr = { "Error: Symbol not found" }

    local out = ListCodeUsagesTool.output.error(tool_context, mock_tools, nil, stderr)
    _G.test_result = { out = out, captured = _G.captured_tool_output }
  ]])
  local res = child.lua_get("_G.test_result")

  h.not_eq(nil, res.out)
  h.eq("Error: Symbol not found", res.captured)
end

T["get_file_extension extracts extension (lua)"] = function()
  child.lua([[
    local cap = {}
    local orig_grep = SymbolFinder.find_with_grep_async
    local orig_lsp = SymbolFinder.find_with_lsp_async
    SymbolFinder.find_with_lsp_async = function(_, _, cb) cb({}) end
    SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb)
      cap.file_ext = file_ext
      cb(nil)
    end

    local tool_context = { args = { symbol_name = "foo" }, chat = _G.tools.chat }
    local done = false
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function() done = true end)
    vim.wait(400, function() return done end, 10)

    SymbolFinder.find_with_grep_async = orig_grep
    SymbolFinder.find_with_lsp_async = orig_lsp
    _G.test_result = cap
  ]])
  local res = child.lua_get("_G.test_result")

  h.eq("lua", res.file_ext)
end

T["get_file_extension handles files without extension"] = function()
  child.lua([[
    -- create a new buffer named 'Makefile' and use as context
    local buf = vim.api.nvim_create_buf(false, true)
    local path = vim.fs.joinpath(_G.TEST_WS, "Makefile")
    vim.api.nvim_buf_set_name(buf, path)

    local orig_ctx = _G.tools.chat.buffer_context.bufnr
    _G.tools.chat.buffer_context.bufnr = buf

    local cap = {}
    local orig_grep = SymbolFinder.find_with_grep_async
    local orig_lsp = SymbolFinder.find_with_lsp_async
    SymbolFinder.find_with_lsp_async = function(_, _, cb) cb({}) end
    SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb)
      cap.file_ext = file_ext
      cb(nil)
    end

    local tool_context = { args = { symbol_name = "foo" }, chat = _G.tools.chat }
    local done = false
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function() done = true end)
    vim.wait(400, function() return done end, 10)

    -- restore
    _G.tools.chat.buffer_context.bufnr = orig_ctx
    SymbolFinder.find_with_grep_async = orig_grep
    SymbolFinder.find_with_lsp_async = orig_lsp
    _G.test_result = cap
  ]])
  local res = child.lua_get("_G.test_result")

  h.eq("*", res.file_ext)
end

T["get_file_extension handles invalid buffer"] = function()
  child.lua([[
    local orig_ctx = _G.tools.chat.buffer_context.bufnr
    _G.tools.chat.buffer_context.bufnr = -1

    local cap = {}
    local orig_grep = SymbolFinder.find_with_grep_async
    local orig_lsp = SymbolFinder.find_with_lsp_async
    SymbolFinder.find_with_lsp_async = function(_, _, cb) cb({}) end
    SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb)
      cap.file_ext = file_ext
      cb(nil)
    end

    local tool_context = { args = { symbol_name = "foo" }, chat = _G.tools.chat }
    local done = false
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function() done = true end)
    vim.wait(400, function() return done end, 10)

    -- restore
    _G.tools.chat.buffer_context.bufnr = orig_ctx
    SymbolFinder.find_with_grep_async = orig_grep
    SymbolFinder.find_with_lsp_async = orig_lsp
    _G.test_result = cap
  ]])

  local res = child.lua_get("_G.test_result")
  h.eq("", res.file_ext)
end

T["Integration"] = new_set()

T["Integration"]["grep-only integration discovers usages and formats output"] = function()
  child.lua([[
    local tool_context = {
      args = { symbol_name = "foo" },
      chat = _G.tools.chat,
    }

    local done = false
    local result_status, result_data

    -- Invoke the tool's main command
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function(res)
      result_status = res.status
      result_data = res.data
      done = true
    end)

    vim.wait(1000, function() return done end, 20)

    -- Now, format the collected results into chat output
    local out = ListCodeUsagesTool.output.success(tool_context, _G.tools, nil, nil)

    _G.test_result = {
      status = result_status,
      capture = _G.captured_tool_output or out,
    }
  ]])

  local res = child.lua_get("_G.test_result")
  h.eq("success", res.status)
  h.expect_contains("Searched for symbol `foo`", res.capture)

  -- Code fences and filenames
  h.expect_contains("```", res.capture)
  h.expect_contains("Filename: src/a.lua:", res.capture)
  h.expect_contains("Filename: src/b.lua:", res.capture)

  -- At least one block should include the function body or its indentation-based fallback
  h.expect_contains("function", res.capture)
end

T["Integration"]["no results returns user-facing error"] = function()
  child.lua([[
    -- Make both LSP and grep return nothing
    SymbolFinder.find_with_lsp_async = function(symbol, file_paths, cb) cb({}) end
    SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb) cb(nil) end
    vim.fn.setqflist({})

    local tool_context = {
      args = { symbol_name = "does_not_exist" },
      chat = _G.tools.chat,
    }

    local done = false
    local result_status, result_data

    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function(res)
      result_status = res.status
      result_data = res.data
      done = true
    end)

    vim.wait(800, function() return done end, 20)

    _G.test_result = {
      status = result_status,
      data = result_data,
    }
  ]])

  local res = child.lua_get("_G.test_result")
  h.eq("error", res.status)
  h.expect_contains("Symbol not found in workspace", res.data)
end

T["Integration"]["lsp documentation is formatted without code fences"] = function()
  child.lua([[
    -- Make LSP return a single symbol and hover documentation
    SymbolFinder.find_with_lsp_async = function(symbol, file_paths, cb)
      cb({
        {
          file = _G.FILE_A,
          range = { start = { line = 0, character = 0 } }, -- top of file A
        },
      })
    end
    SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb)
      cb(nil) -- disable grep for this test
    end

    local Methods = vim.lsp.protocol.Methods
    LspHandler.execute_request_async = function(bufnr, method, cb)
      if method == Methods.textDocument_hover then
        cb({ client1 = { contents = "Doc for foo" } })
      else
        cb({})
      end
    end

    local tool_context = {
      args = { symbol_name = "foo" },
      chat = _G.tools.chat,
    }

    local done, status = false, nil
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function(res)
      status = res.status
      done = true
    end)
    vim.wait(1000, function() return done end, 20)

    local out = ListCodeUsagesTool.output.success(tool_context, _G.tools, nil, nil)
    _G.test_result = { status = status, out = out or _G.captured_tool_output }
  ]])

  local res = child.lua_get("_G.test_result")
  h.eq("success", res.status)
  h.expect_contains("\ndocumentation:\n", res.out)
  h.expect_contains("---\nDoc for foo\n", res.out)

  -- Ensure it's not fenced like code
  h.expect_truthy(not res.out:find("```Doc for foo", 1, true))
end

T["Integration"]["lsp and grep duplicates are merged"] = function()
  child.lua([[
    -- Prepare a single qflist item for the usage in FILE_A line 6
    local bufa = vim.fn.bufnr(_G.FILE_A, true)
    local a_lines = vim.api.nvim_buf_get_lines(bufa, 0, -1, false)
    local function col_of(s, pat) return (s:find(pat, 1, true) or 1) end
    local col = col_of(a_lines[6] or "", "foo")
    vim.fn.setqflist({ { bufnr = bufa, lnum = 6, col = col } })

    -- Symbol at the same location via LSP references
    SymbolFinder.find_with_lsp_async = function(symbol, file_paths, cb)
      cb({
        {
          file = _G.FILE_A,
          range = { start = { line = 5, character = math.max(col - 1, 0) } }, -- 0-indexed
        },
      })
    end
    SymbolFinder.find_with_grep_async = function(symbol, file_ext, file_paths, cb)
      local qf = vim.fn.getqflist()
      local first = qf[1]
      cb({
        file = vim.fn.bufname(first.bufnr),
        line = first.lnum,
        col = first.col,
        bufnr = first.bufnr,
        qflist = qf,
      })
    end

    local Methods = vim.lsp.protocol.Methods
    LspHandler.execute_request_async = function(bufnr, method, cb)
      if method == Methods.textDocument_references then
        cb({
          client1 = {
            { uri = vim.uri_from_fname(_G.FILE_A), range = { start = { line = 5, character = math.max(col - 1, 0) } } },
          },
        })
      else
        cb({})
      end
    end

    local tool_context = {
      args = { symbol_name = "foo" },
      chat = _G.tools.chat,
    }

    local done, status, out = false, nil, nil
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function(res)
      status = res.status
      done = true
    end)
    vim.wait(1000, function() return done end, 20)
    out = ListCodeUsagesTool.output.success(tool_context, _G.tools, nil, nil)

    -- Count occurrences of the a.lua filename header (should be exactly one)
    local _, count = (out or _G.captured_tool_output):gsub("Filename: src/a.lua:", "")
    _G.test_result = { status = status, count = count }
  ]])

  local res = child.lua_get("_G.test_result")
  h.eq("success", res.status)
  h.eq(1, res.count)
end

T["Integration"]["returns to chat window"] = function()
  child.lua([[
    -- Identify the chat window (the one not equal to context)
    local ctx = _G.tools.chat.buffer_context.winnr
    local chat_win
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= ctx then chat_win = w end
    end

    SymbolFinder.find_with_lsp_async = function(_, _, cb) cb({}) end
    SymbolFinder.find_with_grep_async = function(_, _, _, cb)
      cb(nil) -- Force no results to take the error path
    end
    vim.fn.setqflist({})

    local tool_context = { args = { symbol_name = "noop" }, chat = _G.tools.chat }
    local done = false
    ListCodeUsagesTool.cmds[1](tool_context, tool_context.args, nil, function() done = true end)
    vim.wait(600, function() return done end, 20)

    _G.test_result = { current_win = vim.api.nvim_get_current_win(), expected = chat_win }
  ]])

  local res = child.lua_get("_G.test_result")
  h.eq(res.expected, res.current_win)
end

return T
