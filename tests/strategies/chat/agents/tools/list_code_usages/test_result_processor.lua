local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Load the ResultProcessor module
        ResultProcessor = require("codecompanion.strategies.chat.agents.tools.list_code_usages.result_processor")
        Utils = require("codecompanion.strategies.chat.agents.tools.list_code_usages.utils")
        CodeExtractor = require("codecompanion.strategies.chat.agents.tools.list_code_usages.code_extractor")
        
        -- Mock vim.uri_to_bufnr
        _G.mock_uri_to_bufnr = {}
        vim.uri_to_bufnr = function(uri)
          return _G.mock_uri_to_bufnr[uri] or 1
        end
        
        -- Mock vim.fn.bufload
        _G.mock_bufload_calls = {}
        vim.fn.bufload = function(bufnr)
          _G.mock_bufload_calls[#_G.mock_bufload_calls + 1] = bufnr
        end
        
        -- Mock vim.api.nvim_buf_is_loaded
        _G.mock_buf_loaded = {}
        vim.api.nvim_buf_is_loaded = function(bufnr)
          return _G.mock_buf_loaded[bufnr] or false
        end
        
        -- Mock CodeExtractor.get_code_block_at_position
        _G.mock_code_extractor_results = {}
        CodeExtractor.get_code_block_at_position = function(bufnr, row, col)
          local key = string.format("%d:%d:%d", bufnr, row, col)
          return _G.mock_code_extractor_results[key] or Utils.create_result("error", "No mock result")
        end
        
        -- Helper to create test code block
        function create_test_code_block(filename, start_line, end_line, code_block)
          return {
            filename = filename,
            start_line = start_line,
            end_line = end_line,
            code_block = code_block or "test code",
            filetype = "lua"
          }
        end
        
        -- Helper to reset mock state
        function reset_mock_state()
          _G.mock_uri_to_bufnr = {}
          _G.mock_bufload_calls = {}
          _G.mock_buf_loaded = {}
          _G.mock_code_extractor_results = {}
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["is_duplicate_or_enclosed"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["is_duplicate_or_enclosed"]["detects exact duplicates"] = function()
  child.lua([[
    local new_block = create_test_code_block("test.lua", 10, 20)
    local symbol_data = {
      references = {
        create_test_code_block("test.lua", 10, 20), -- Exact duplicate
        create_test_code_block("other.lua", 5, 15)
      }
    }
    
    local result = ResultProcessor.is_duplicate_or_enclosed(new_block, symbol_data)
    
    _G.test_result = result
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["is_duplicate_or_enclosed"]["detects enclosed blocks"] = function()
  child.lua([[
    local new_block = create_test_code_block("test.lua", 12, 15) -- Smaller block
    local symbol_data = {
      references = {
        create_test_code_block("test.lua", 10, 20), -- Larger enclosing block
      }
    }
    
    local result = ResultProcessor.is_duplicate_or_enclosed(new_block, symbol_data)
    
    _G.test_result = result
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["is_duplicate_or_enclosed"]["returns false for unique blocks"] = function()
  child.lua([[
    local new_block = create_test_code_block("test.lua", 25, 30)
    local symbol_data = {
      references = {
        create_test_code_block("test.lua", 10, 20),
        create_test_code_block("other.lua", 5, 15)
      }
    }
    
    local result = ResultProcessor.is_duplicate_or_enclosed(new_block, symbol_data)
    
    _G.test_result = result
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

T["is_duplicate_or_enclosed"]["skips blocks without required fields"] = function()
  child.lua([[
    local new_block = create_test_code_block("test.lua", 10, 20)
    local symbol_data = {
      documentation = {
        { code_block = "some docs" }, -- Missing filename, start_line, end_line
      },
      references = {
        create_test_code_block("other.lua", 5, 15)
      }
    }
    
    local result = ResultProcessor.is_duplicate_or_enclosed(new_block, symbol_data)
    
    _G.test_result = result
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(false, result) -- Should not match documentation block
end

T["is_duplicate_or_enclosed"]["handles empty symbol_data"] = function()
  child.lua([[
    local new_block = create_test_code_block("test.lua", 10, 20)
    local symbol_data = {}
    
    local result = ResultProcessor.is_duplicate_or_enclosed(new_block, symbol_data)
    
    _G.test_result = result
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

T["process_lsp_item"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["process_lsp_item"]["processes valid LSP item successfully"] = function()
  child.lua([[
    local uri = "file:///test/file.lua"
    local range = { start = { line = 5, character = 0 } }
    local symbol_data = {}
    
    _G.mock_uri_to_bufnr[uri] = 1
    _G.mock_code_extractor_results["1:5:0"] = Utils.create_result("success", 
      create_test_code_block("file.lua", 6, 10, "function test()"))
    
    local result = ResultProcessor.process_lsp_item(uri, range, "references", symbol_data)
    
    _G.test_result = {
      result = result,
      symbol_data = symbol_data,
      bufload_calls = _G.mock_bufload_calls
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq("success", result.result.status)
  h.eq("Symbol processed", result.result.data)
  h.eq(1, #result.symbol_data.references)
  h.eq("file.lua", result.symbol_data.references[1].filename)
  h.eq(1, #result.bufload_calls) -- Should have called bufload
end

T["process_lsp_item"]["returns error for missing uri or range"] = function()
  child.lua([[
    local result1 = ResultProcessor.process_lsp_item(nil, { start = { line = 5, character = 0 } }, "references", {})
    local result2 = ResultProcessor.process_lsp_item("file:///test.lua", nil, "references", {})
    
    _G.test_result = {
      result1 = result1,
      result2 = result2
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq("error", result.result1.status)
  h.eq("error", result.result2.status)
  h.expect_contains("Missing uri or range", result.result1.data)
  h.expect_contains("Missing uri or range", result.result2.data)
end

T["process_lsp_item"]["handles code extraction failure"] = function()
  child.lua([[
    local uri = "file:///test/file.lua"
    local range = { start = { line = 5, character = 0 } }
    local symbol_data = {}
    
    _G.mock_uri_to_bufnr[uri] = 1
    _G.mock_code_extractor_results["1:5:0"] = Utils.create_result("error", "Extraction failed")
    
    local result = ResultProcessor.process_lsp_item(uri, range, "references", symbol_data)
    
    _G.test_result = result
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq("error", result.status)
  h.eq("Extraction failed", result.data)
end

T["process_lsp_item"]["skips duplicate blocks"] = function()
  child.lua([[
    local uri = "file:///test/file.lua"
    local range = { start = { line = 5, character = 0 } }
    local symbol_data = {
      references = {
        create_test_code_block("file.lua", 6, 10) -- Pre-existing block
      }
    }
    
    _G.mock_uri_to_bufnr[uri] = 1
    _G.mock_code_extractor_results["1:5:0"] = Utils.create_result("success", 
      create_test_code_block("file.lua", 6, 10)) -- Same block
    
    local result = ResultProcessor.process_lsp_item(uri, range, "references", symbol_data)
    
    _G.test_result = {
      result = result,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq("success", result.result.status)
  h.eq("Duplicate or enclosed entry", result.result.data)
  h.eq(1, #result.symbol_data.references) -- Should still have only 1 item
end

T["process_documentation_item"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["process_documentation_item"]["processes string content"] = function()
  child.lua([[
    local symbol_data = {}
    local result_data = { contents = "This is documentation content" }
    
    local result = ResultProcessor.process_documentation_item(symbol_data, "documentation", result_data)
    
    _G.test_result = {
      result = result,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq("success", result.result.status)
  h.eq("documentation processed", result.result.data)
  h.eq(1, #result.symbol_data.documentation)
  h.eq("This is documentation content", result.symbol_data.documentation[1].code_block)
end

T["process_documentation_item"]["processes table content (jdtls format)"] = function()
  child.lua([[
    local symbol_data = {}
    local result_data = { 
      contents = { "prefix", "middle", "This is the actual documentation" }
    }
    
    local result = ResultProcessor.process_documentation_item(symbol_data, "documentation", result_data)
    
    _G.test_result = {
      result = result,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq("success", result.result.status)
  h.eq(1, #result.symbol_data.documentation)
  h.eq("This is the actual documentation", result.symbol_data.documentation[1].code_block)
end

T["process_documentation_item"]["skips duplicate documentation"] = function()
  child.lua([[
    local symbol_data = {
      documentation = {
        { code_block = "Existing documentation" }
      }
    }
    local result_data = { contents = "Existing documentation" } -- Duplicate
    
    local result = ResultProcessor.process_documentation_item(symbol_data, "documentation", result_data)
    
    _G.test_result = {
      result = result,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq("success", result.result.status)
  h.eq(1, #result.symbol_data.documentation) -- Should still have only 1 item
end

T["process_lsp_results"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["process_lsp_results"]["processes documentation results"] = function()
  child.lua([[
    local lsp_results = {
      client1 = { contents = "Documentation from client1" },
      client2 = { contents = "Documentation from client2" }
    }
    local symbol_data = {}
    
    local count = ResultProcessor.process_lsp_results(lsp_results, "documentation", symbol_data)
    
    _G.test_result = {
      count = count,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(2, result.count)
  h.eq(2, #result.symbol_data.documentation)
end

T["process_lsp_results"]["processes single item with range"] = function()
  child.lua([[
    local lsp_results = {
      client1 = {
        uri = "file:///test.lua",
        range = { start = { line = 5, character = 0 } }
      }
    }
    local symbol_data = {}
    
    _G.mock_uri_to_bufnr["file:///test.lua"] = 1
    _G.mock_code_extractor_results["1:5:0"] = Utils.create_result("success", 
      create_test_code_block("test.lua", 6, 10))
    
    local count = ResultProcessor.process_lsp_results(lsp_results, "references", symbol_data)
    
    _G.test_result = {
      count = count,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(1, result.count)
  h.eq(1, #result.symbol_data.references)
end

T["process_lsp_results"]["processes array of items"] = function()
  child.lua([[
    local lsp_results = {
      client1 = {
        {
          uri = "file:///test1.lua",
          range = { start = { line = 5, character = 0 } }
        },
        {
          targetUri = "file:///test2.lua", -- Alternative field name
          targetSelectionRange = { start = { line = 10, character = 0 } } -- Alternative field name
        }
      }
    }
    local symbol_data = {}
    
    _G.mock_uri_to_bufnr["file:///test1.lua"] = 1
    _G.mock_uri_to_bufnr["file:///test2.lua"] = 2
    _G.mock_code_extractor_results["1:5:0"] = Utils.create_result("success", 
      create_test_code_block("test1.lua", 6, 10))
    _G.mock_code_extractor_results["2:10:0"] = Utils.create_result("success", 
      create_test_code_block("test2.lua", 11, 15))
    
    local count = ResultProcessor.process_lsp_results(lsp_results, "references", symbol_data)
    
    _G.test_result = {
      count = count,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(2, result.count)
  h.eq(2, #result.symbol_data.references)
end

T["process_lsp_results"]["excludes duplicates from count"] = function()
  child.lua([[
    local lsp_results = {
      client1 = {
        {
          uri = "file:///test.lua",
          range = { start = { line = 5, character = 0 } }
        }
      }
    }
    local symbol_data = {}
    
    _G.mock_uri_to_bufnr["file:///test.lua"] = 1
    -- Mock to return duplicate result
    _G.mock_code_extractor_results["1:5:0"] = Utils.create_result("success", 
      create_test_code_block("test.lua", 6, 10))
    
    -- First call should add the item
    local count1 = ResultProcessor.process_lsp_results(lsp_results, "references", symbol_data)
    
    -- Second call with same data should detect duplicate
    local count2 = ResultProcessor.process_lsp_results(lsp_results, "references", symbol_data)
    
    _G.test_result = {
      count1 = count1,
      count2 = count2,
      total_items = #symbol_data.references
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(1, result.count1) -- First call should count the item
  h.eq(0, result.count2) -- Second call should not count duplicates
  h.eq(1, result.total_items) -- Should still have only 1 item
end

T["process_quickfix_references"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["process_quickfix_references"]["processes quickfix list successfully"] = function()
  child.lua([[
    local qflist = {
      { bufnr = 1, lnum = 10, col = 5 },
      { bufnr = 2, lnum = 20, col = 8 }
    }
    local symbol_data = {}
    
    _G.mock_buf_loaded[1] = true -- Buffer 1 is already loaded
    _G.mock_buf_loaded[2] = false -- Buffer 2 needs loading
    
    _G.mock_code_extractor_results["1:9:4"] = Utils.create_result("success", 
      create_test_code_block("file1.lua", 10, 15))
    _G.mock_code_extractor_results["2:19:7"] = Utils.create_result("success", 
      create_test_code_block("file2.lua", 20, 25))
    
    local count = ResultProcessor.process_quickfix_references(qflist, symbol_data)
    
    _G.test_result = {
      count = count,
      symbol_data = symbol_data,
      bufload_calls = _G.mock_bufload_calls
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(2, result.count)
  h.eq(2, #result.symbol_data.grep)
  h.eq(1, #result.bufload_calls) -- Should have loaded buffer 2
  h.eq(2, result.bufload_calls[1]) -- Buffer 2 was loaded
end

T["process_quickfix_references"]["handles empty quickfix list"] = function()
  child.lua([[
    local count1 = ResultProcessor.process_quickfix_references(nil, {})
    local count2 = ResultProcessor.process_quickfix_references({}, {})
    
    _G.test_result = {
      count1 = count1,
      count2 = count2
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(0, result.count1)
  h.eq(0, result.count2)
end

T["process_quickfix_references"]["skips items without bufnr or lnum"] = function()
  child.lua([[
    local qflist = {
      { bufnr = 1, lnum = 10, col = 5 }, -- Valid
      { lnum = 20, col = 8 }, -- Missing bufnr
      { bufnr = 3, col = 12 }, -- Missing lnum
      { bufnr = 4, lnum = 30, col = 15 } -- Valid
    }
    local symbol_data = {}
    
    _G.mock_code_extractor_results["1:9:4"] = Utils.create_result("success", 
      create_test_code_block("file1.lua", 10, 15))
    _G.mock_code_extractor_results["4:29:14"] = Utils.create_result("success", 
      create_test_code_block("file4.lua", 30, 35))
    
    local count = ResultProcessor.process_quickfix_references(qflist, symbol_data)
    
    _G.test_result = {
      count = count,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(2, result.count) -- Should only process 2 valid items
  h.eq(2, #result.symbol_data.grep)
end

T["process_quickfix_references"]["handles code extraction failures"] = function()
  child.lua([[
    local qflist = {
      { bufnr = 1, lnum = 10, col = 5 }, -- Will succeed
      { bufnr = 2, lnum = 20, col = 8 }  -- Will fail
    }
    local symbol_data = {}
    
    _G.mock_code_extractor_results["1:9:4"] = Utils.create_result("success", 
      create_test_code_block("file1.lua", 10, 15))
    _G.mock_code_extractor_results["2:19:7"] = Utils.create_result("error", "Extraction failed")
    
    local count = ResultProcessor.process_quickfix_references(qflist, symbol_data)
    
    _G.test_result = {
      count = count,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(1, result.count) -- Should only count successful extractions
  h.eq(1, #result.symbol_data.grep)
end

T["process_quickfix_references"]["skips duplicate blocks"] = function()
  child.lua([[
    local qflist = {
      { bufnr = 1, lnum = 10, col = 5 },
      { bufnr = 1, lnum = 12, col = 8 } -- Different position but same extracted block
    }
    local symbol_data = {}
    
    -- Both positions extract the same code block
    local same_block = create_test_code_block("file1.lua", 10, 15)
    _G.mock_code_extractor_results["1:9:4"] = Utils.create_result("success", same_block)
    _G.mock_code_extractor_results["1:11:7"] = Utils.create_result("success", same_block)
    
    local count = ResultProcessor.process_quickfix_references(qflist, symbol_data)
    
    _G.test_result = {
      count = count,
      symbol_data = symbol_data
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(1, result.count) -- Should only count unique blocks
  h.eq(1, #result.symbol_data.grep)
end

T["process_quickfix_references"]["converts line and column numbers correctly"] = function()
  child.lua([[
    local qflist = {
      { bufnr = 1, lnum = 15, col = 10 } -- 1-indexed input
    }
    local symbol_data = {}
    
    -- Should be converted to 0-indexed: line 14, col 9
    _G.mock_code_extractor_results["1:14:9"] = Utils.create_result("success", 
      create_test_code_block("file1.lua", 15, 20))
    
    local count = ResultProcessor.process_quickfix_references(qflist, symbol_data)
    
    _G.test_result = {
      count = count,
      extractor_key_found = _G.mock_code_extractor_results["1:14:9"] ~= nil
    }
  ]])
  
  local result = child.lua_get("_G.test_result")
  h.eq(1, result.count)
  h.eq(true, result.extractor_key_found) -- Confirms correct conversion
end

return T