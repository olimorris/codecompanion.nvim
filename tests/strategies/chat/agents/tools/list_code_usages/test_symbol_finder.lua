local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Load the SymbolFinder module
        SymbolFinder = require("codecompanion.strategies.chat.agents.tools.list_code_usages.symbol_finder")
        Utils = require("codecompanion.strategies.chat.agents.tools.list_code_usages.utils")

        -- Mock vim.lsp functions for testing
        _G.mock_lsp = {
          clients = {},
          results = {},
          method_calls = {}
        }

        -- Mock vim.lsp.get_clients
        vim.lsp.get_clients = function(opts)
          _G.mock_lsp.method_calls[#_G.mock_lsp.method_calls + 1] = { func = "get_clients", opts = opts }
          return _G.mock_lsp.clients
        end

        -- Mock vim.fn.getqflist
        _G.mock_qflist = {}
        vim.fn.getqflist = function()
          return _G.mock_qflist
        end

        -- Mock vim.fn.bufname
        vim.fn.bufname = function(bufnr)
          return "/test/file" .. bufnr .. ".lua"
        end

        -- Mock vim.cmd for grep commands
        _G.mock_grep_success = true
        _G.mock_grep_commands = {}
        local original_vim_cmd = vim.cmd
        vim.cmd = function(cmd)
          if type(cmd) == "string" and cmd:match("^silent! grep!") then
            _G.mock_grep_commands[#_G.mock_grep_commands + 1] = cmd
            if not _G.mock_grep_success then
              error("Grep command failed")
            end
            return
          end
          return original_vim_cmd(cmd)
        end

        -- Helper to create mock LSP client
        function create_mock_client(name, id)
          return {
            name = name,
            id = id,
            request = function(self, method, params, callback)
              _G.mock_lsp.method_calls[#_G.mock_lsp.method_calls + 1] = {
                func = "request",
                client = self.name,
                method = method,
                params = params
              }

              -- Simulate async callback
              vim.schedule(function()
                local result = _G.mock_lsp.results[self.name] or {}
                callback(nil, result, nil, nil)
              end)
            end
          }
        end

        -- Helper to reset mock state
        function reset_mock_state()
          _G.mock_lsp = {
            clients = {},
            results = {},
            method_calls = {}
          }
          _G.mock_qflist = {}
          _G.mock_grep_success = true
          _G.mock_grep_commands = {}
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["find_with_lsp_async"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["find_with_lsp_async"]["handles no LSP clients available"] = function()
  child.lua([[
    _G.mock_lsp.clients = {} -- No clients

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_lsp_async("testSymbol", nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(100)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq({}, result.result)
end

T["find_with_lsp_async"]["finds symbols with single client"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {
      {
        name = "testSymbol",
        kind = 12, -- Function kind
        location = {
          uri = "file:///project/test.lua",
          range = { start = { line = 5, character = 0 }, ["end"] = { line = 5, character = 10 } }
        }
      },
      {
        name = "otherSymbol", -- Should be filtered out
        kind = 13,
        location = {
          uri = "file:///project/other.lua",
          range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 11 } }
        }
      }
    }

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_lsp_async("testSymbol", nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result,
      method_calls = _G.mock_lsp.method_calls
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(1, #result.result) -- Should only have 1 matching symbol

  local symbol = result.result[1]
  h.eq("testSymbol", symbol.name)
  h.eq(12, symbol.kind)
  h.eq("file:///project/test.lua", symbol.uri)
  h.eq("/project/test.lua", symbol.file)

  -- Check that workspace_symbol method was called
  local request_call = nil
  for _, call in ipairs(result.method_calls) do
    if call.func == "request" then
      request_call = call
      break
    end
  end
  h.not_eq(nil, request_call)
  h.eq(vim.lsp.protocol.Methods.workspace_symbol, request_call.method)
  h.eq("testSymbol", request_call.params.query)
end

T["find_with_lsp_async"]["finds symbols with multiple clients"] = function()
  child.lua([[
    local client1 = create_mock_client("client1", 1)
    local client2 = create_mock_client("client2", 2)
    _G.mock_lsp.clients = { client1, client2 }

    _G.mock_lsp.results["client1"] = {
      {
        name = "testSymbol",
        kind = 12,
        location = {
          uri = "file:///project/test1.lua",
          range = { start = { line = 5, character = 0 }, ["end"] = { line = 5, character = 10 } }
        }
      }
    }

    _G.mock_lsp.results["client2"] = {
      {
        name = "testSymbol",
        kind = 6, -- Class kind (lower number, higher priority)
        location = {
          uri = "file:///project/test2.lua",
          range = { start = { line = 10, character = 0 }, ["end"] = { line = 10, character = 10 } }
        }
      }
    }

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_lsp_async("testSymbol", nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(300)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(2, #result.result)

  -- Should be sorted by kind (lower numbers first)
  h.eq(6, result.result[1].kind) -- Class kind should come first
  h.eq(12, result.result[2].kind) -- Function kind should come second
end

T["find_with_lsp_async"]["filters symbols by filepaths"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {
      {
        name = "testSymbol",
        kind = 12,
        location = {
          uri = "file:///project/src/main.lua",
          range = { start = { line = 5, character = 0 }, ["end"] = { line = 5, character = 10 } }
        }
      },
      {
        name = "testSymbol",
        kind = 13,
        location = {
          uri = "file:///project/test/spec.lua", -- Should be filtered out
          range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 10 } }
        }
      }
    }

    local callback_called = false
    local callback_result = nil

    -- Filter to only include files with "src" in the path
    SymbolFinder.find_with_lsp_async("testSymbol", {"src"}, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(1, #result.result) -- Should only have 1 symbol after filtering
  h.expect_contains("src", result.result[1].file)
end

T["find_with_lsp_async"]["handles empty results from client"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {} -- Empty results

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_lsp_async("testSymbol", nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq({}, result.result)
end

T["find_with_grep_async"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["find_with_grep_async"]["finds symbols with grep"] = function()
  child.lua([[
    -- Mock quickfix list with results
    _G.mock_qflist = {
      {
        bufnr = 1,
        lnum = 10,
        col = 5,
        text = "function testSymbol() {"
      },
      {
        bufnr = 2,
        lnum = 20,
        col = 8,
        text = "local testSymbol = 42"
      }
    }

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_grep_async("testSymbol", nil, nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result,
      grep_commands = _G.mock_grep_commands
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.not_eq(nil, result.result)

  -- Should return first match details
  h.eq("/test/file1.lua", result.result.file)
  h.eq(10, result.result.line)
  h.eq(5, result.result.col)
  h.eq("function testSymbol() {", result.result.text)
  h.eq(1, result.result.bufnr)
  h.eq(2, #result.result.qflist) -- Should include full qflist

  -- Check that grep command was executed
  h.eq(1, #result.grep_commands)
  h.expect_contains("grep!", result.grep_commands[1])
  h.expect_contains("testSymbol", result.grep_commands[1])
end

T["find_with_grep_async"]["includes file extension filter"] = function()
  child.lua([[
    _G.mock_qflist = {
      {
        bufnr = 1,
        lnum = 10,
        col = 5,
        text = "function testSymbol() {"
      }
    }

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_grep_async("testSymbol", "lua", nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result,
      grep_commands = _G.mock_grep_commands
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.not_eq(nil, result.result)

  -- Check that file extension filter was included in grep command
  h.eq(1, #result.grep_commands)
  h.expect_contains("--glob='*.lua'", result.grep_commands[1])
end

T["find_with_grep_async"]["includes directory exclusions"] = function()
  child.lua([[
    _G.mock_qflist = {
      {
        bufnr = 1,
        lnum = 10,
        col = 5,
        text = "function testSymbol() {"
      }
    }

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_grep_async("testSymbol", nil, nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result,
      grep_commands = _G.mock_grep_commands
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)

  -- Check that exclusion patterns are included
  local grep_cmd = result.grep_commands[1]
  h.expect_contains("--glob=!'node_modules/**'", grep_cmd)
  h.expect_contains("--glob=!'.git/**'", grep_cmd)
  h.expect_contains("--glob=!'dist/**'", grep_cmd)
end

T["find_with_grep_async"]["includes filepaths in command"] = function()
  child.lua([[
    _G.mock_qflist = {
      {
        bufnr = 1,
        lnum = 10,
        col = 5,
        text = "function testSymbol() {"
      }
    }

    local callback_called = false
    local callback_result = nil

    local filepaths = {"src/main.lua", "lib/utils.lua"}
    SymbolFinder.find_with_grep_async("testSymbol", nil, filepaths, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result,
      grep_commands = _G.mock_grep_commands
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)

  -- Check that filepaths are included in grep command
  local grep_cmd = result.grep_commands[1]
  h.expect_contains("src/main.lua", grep_cmd)
  h.expect_contains("lib/utils.lua", grep_cmd)
end

T["find_with_grep_async"]["handles grep command failure"] = function()
  child.lua([[
    _G.mock_grep_success = false -- Make grep command fail

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_grep_async("testSymbol", nil, nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(nil, result.result) -- Should return nil on failure
end

T["find_with_grep_async"]["handles empty quickfix list"] = function()
  child.lua([[
    _G.mock_qflist = {} -- Empty quickfix list

    local callback_called = false
    local callback_result = nil

    SymbolFinder.find_with_grep_async("testSymbol", nil, nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(nil, result.result) -- Should return nil when no matches
end

T["find_with_grep_async"]["escapes special characters in symbol name"] = function()
  child.lua([[
    _G.mock_qflist = {
      {
        bufnr = 1,
        lnum = 10,
        col = 5,
        text = "function test$symbol() {"
      }
    }

    local callback_called = false
    local callback_result = nil

    -- Test with symbol containing special characters
    SymbolFinder.find_with_grep_async("test$symbol", nil, nil, function(result)
      callback_called = true
      callback_result = result
    end)

    vim.wait(200)

    _G.test_result = {
      callback_called = callback_called,
      result = callback_result,
      grep_commands = _G.mock_grep_commands
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.not_eq(nil, result.result)

  -- The symbol should be quoted in the grep command (vim.fn.shellescape handles the escaping)
  local grep_cmd = result.grep_commands[1]
  h.expect_contains("'test$symbol'", grep_cmd)
end

return T

