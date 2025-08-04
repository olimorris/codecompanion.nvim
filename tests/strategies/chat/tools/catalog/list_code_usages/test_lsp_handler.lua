local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Load the LspHandler module
        LspHandler = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.lsp_handler")
        Utils = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.utils")

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

        -- Mock vim.lsp.buf_is_attached
        vim.lsp.buf_is_attached = function(bufnr, client_id)
          return false -- Default to not attached for testing attachment logic
        end

        -- Mock vim.lsp.buf_attach_client
        vim.lsp.buf_attach_client = function(bufnr, client_id)
          _G.mock_lsp.method_calls[#_G.mock_lsp.method_calls + 1] = {
            func = "buf_attach_client",
            bufnr = bufnr,
            client_id = client_id
          }
        end

        -- Mock vim.lsp.util.make_position_params
        vim.lsp.util.make_position_params = function(winnr, encoding)
          return {
            textDocument = { uri = "file:///test/file.lua" },
            position = { line = 0, character = 0 }
          }
        end

        -- Helper to create mock LSP client
        function create_mock_client(name, id)
          return {
            name = name,
            id = id,
            offset_encoding = "utf-8",
            request = function(self, method, params, callback, bufnr)
              _G.mock_lsp.method_calls[#_G.mock_lsp.method_calls + 1] = {
                func = "request",
                client = self.name,
                method = method,
                params = params,
                bufnr = bufnr
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
        function reset_mock_lsp()
          _G.mock_lsp = {
            clients = {},
            results = {},
            method_calls = {}
          }
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["filter_project_references"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_lsp()]])
    end,
  },
})

T["filter_project_references"]["filters references to project directory only"] = function()
  child.lua([[
    -- Mock project directory
    vim.fn.getcwd = function() return "/project/root" end

    local references = {
      { uri = "file:///project/root/src/file1.lua" },
      { uri = "file:///project/root/lib/file2.lua" },
      { uri = "file:///external/lib/file3.lua" },
      { uri = "file:///project/root/test/file4.lua" },
      { uri = nil }, -- Invalid reference
    }

    local filtered = LspHandler.filter_project_references(references)

    -- Should only include references within project directory
    _G.test_result = {
      count = #filtered,
      uris = {}
    }

    for i, ref in ipairs(filtered) do
      _G.test_result.uris[i] = ref.uri
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(3, result.count)
  h.expect_tbl_contains("file:///project/root/src/file1.lua", result.uris)
  h.expect_tbl_contains("file:///project/root/lib/file2.lua", result.uris)
  h.expect_tbl_contains("file:///project/root/test/file4.lua", result.uris)
end

T["filter_project_references"]["handles empty references list"] = function()
  child.lua([[
    local filtered = LspHandler.filter_project_references({})
    _G.test_result = #filtered
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(0, result)
end

T["filter_project_references"]["handles references with no uri"] = function()
  child.lua([[
    local references = {
      { uri = nil },
      { range = { start = { line = 1, character = 0 } } }, -- No uri field
    }

    local filtered = LspHandler.filter_project_references(references)
    _G.test_result = #filtered
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(0, result)
end

T["execute_request_async"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_lsp()]])
    end,
  },
})

T["execute_request_async"]["handles no LSP clients available"] = function()
  child.lua([[
    _G.mock_lsp.clients = {} -- No clients

    local callback_called = false
    local callback_result = nil

    LspHandler.execute_request_async(1, "textDocument/references", function(result)
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

T["execute_request_async"]["executes request with single client"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {
      { uri = "file:///project/root/test.lua", range = { start = { line = 1, character = 0 } } }
    }

    local callback_called = false
    local callback_result = nil

    LspHandler.execute_request_async(1, "textDocument/references", function(result)
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
  h.not_eq(nil, result.result["test_client"])

  -- Check that client was attached
  local attach_call = nil
  for _, call in ipairs(result.method_calls) do
    if call.func == "buf_attach_client" then
      attach_call = call
      break
    end
  end
  h.not_eq(nil, attach_call)
  h.eq(1, attach_call.bufnr)
  h.eq(1, attach_call.client_id)
end

T["execute_request_async"]["executes request with multiple clients"] = function()
  child.lua([[
    local client1 = create_mock_client("client1", 1)
    local client2 = create_mock_client("client2", 2)
    _G.mock_lsp.clients = { client1, client2 }

    _G.mock_lsp.results["client1"] = {
      { uri = "file:///project/root/test1.lua" }
    }
    _G.mock_lsp.results["client2"] = {
      { uri = "file:///project/root/test2.lua" }
    }

    local callback_called = false
    local callback_result = nil

    LspHandler.execute_request_async(1, "textDocument/references", function(result)
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
  h.not_eq(nil, result.result["client1"])
  h.not_eq(nil, result.result["client2"])
end

T["execute_request_async"]["handles hover documentation method"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {
      contents = {
        value = "Test documentation content"
      },
      range = { start = { line = 1, character = 0 } }
    }

    local callback_called = false
    local callback_result = nil

    LspHandler.execute_request_async(1, vim.lsp.protocol.Methods.textDocument_hover, function(result)
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

  local client_result = result.result["test_client"]
  h.not_eq(nil, client_result)
  h.eq("Test documentation content", client_result.contents)
  h.not_eq(nil, client_result.range)
end

T["execute_request_async"]["handles hover documentation with string contents"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {
      contents = "Direct string content",
      range = { start = { line = 1, character = 0 } }
    }

    local callback_called = false
    local callback_result = nil

    LspHandler.execute_request_async(1, vim.lsp.protocol.Methods.textDocument_hover, function(result)
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

  local client_result = result.result["test_client"]
  h.eq("Direct string content", client_result.contents)
end

T["execute_request_async"]["filters references for references method"] = function()
  child.lua([[
    -- Mock project directory
    vim.fn.getcwd = function() return "/project/root" end

    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {
      { uri = "file:///project/root/src/file1.lua" },
      { uri = "file:///external/lib/file2.lua" }, -- Should be filtered out
      { uri = "file:///project/root/test/file3.lua" },
    }

    local callback_called = false
    local callback_result = nil

    LspHandler.execute_request_async(1, vim.lsp.protocol.Methods.textDocument_references, function(result)
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

  local client_result = result.result["test_client"]
  h.eq(2, #client_result) -- Should only have 2 references after filtering
end

T["execute_request_async"]["handles client with no results"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    -- No results set for this client

    local callback_called = false
    local callback_result = nil

    LspHandler.execute_request_async(1, "textDocument/references", function(result)
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
  -- When no results are set, the client result should be nil or empty
  local client_result = result.result["test_client"]
  h.expect_truthy(client_result == nil or vim.tbl_isempty(client_result))
end

T["execute_request_async"]["sets correct position params"] = function()
  child.lua([[
    local client = create_mock_client("test_client", 1)
    _G.mock_lsp.clients = { client }
    _G.mock_lsp.results["test_client"] = {}

    LspHandler.execute_request_async(1, "textDocument/references", function(result) end)

    vim.wait(200)

    -- Find the request call
    local request_call = nil
    for _, call in ipairs(_G.mock_lsp.method_calls) do
      if call.func == "request" then
        request_call = call
        break
      end
    end

    _G.test_result = {
      request_call = request_call
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.not_eq(nil, result.request_call)
  h.eq("textDocument/references", result.request_call.method)
  h.eq(false, result.request_call.params.context.includeDeclaration)
end

return T
