local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Load the CodeExtractor module
        CodeExtractor = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.code_extractor")
        Utils = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.utils")

        -- Create test buffer with sample code
        function create_test_buffer(content, filetype)
          local bufnr = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
          if filetype then
            vim.api.nvim_set_option_value("filetype", filetype, { buf = bufnr })
          end
          return bufnr
        end

        -- Mock treesitter functions for testing
        _G.mock_treesitter = {
          parser_available = true,
          trees = {},
          nodes = {},
          query_available = true,
          query_captures = {}
        }

        -- Mock vim.treesitter.get_parser
        vim.treesitter.get_parser = function(bufnr)
          if not _G.mock_treesitter.parser_available then
            error("No parser available")
          end

          return {
            parse = function()
              return _G.mock_treesitter.trees
            end,
            lang = function()
              return "lua"
            end
          }
        end

        -- Mock vim.treesitter.query.get
        vim.treesitter.query.get = function(lang, query_type)
          if not _G.mock_treesitter.query_available then
            return nil
          end

          return {
            captures = { "local.scope" },
            iter_captures = function(self, root, bufnr)
              local captures = _G.mock_treesitter.query_captures
              local i = 0
              return function()
                i = i + 1
                if i <= #captures then
                  local capture = captures[i]
                  return capture.id, capture.node, capture.meta
                end
                return nil
              end
            end
          }
        end

        -- Helper to create mock TreeSitter node
        function create_mock_node(node_type, start_row, start_col, end_row, end_col, parent)
          return {
            type = function() return node_type end,
            range = function() return start_row, start_col, end_row, end_col end,
            parent = function() return parent end,
            named_descendant_for_range = function(self, sr, sc, er, ec)
              -- Return self if position is within range
              local my_sr, my_sc, my_er, my_ec = self:range()
              if sr >= my_sr and sr <= my_er and sc >= my_sc and sc <= my_ec then
                return self
              end
              return nil
            end
          }
        end

        -- Helper to create mock tree
        function create_mock_tree(root_node)
          return {
            root = function() return root_node end
          }
        end

        -- Helper to reset mock state
        function reset_mock_treesitter()
          _G.mock_treesitter = {
            parser_available = true,
            trees = {},
            nodes = {},
            query_available = true,
            query_captures = {}
          }
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["get_block_with_locals"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_treesitter()]])
    end,
  },
})

T["get_block_with_locals"]["returns nil when no parser available"] = function()
  child.lua([[
    _G.mock_treesitter.parser_available = false

    local bufnr = create_test_buffer({"function test()", "  return 42", "end"}, "lua")
    local result = CodeExtractor.get_block_with_locals(bufnr, 1, 0)

    _G.test_result = result == nil
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["get_block_with_locals"]["returns nil when no trees available"] = function()
  child.lua([[
    _G.mock_treesitter.trees = {} -- Empty trees

    local bufnr = create_test_buffer({"function test()", "  return 42", "end"}, "lua")
    local result = CodeExtractor.get_block_with_locals(bufnr, 1, 0)

    _G.test_result = result == nil
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["get_block_with_locals"]["returns node when no locals query available"] = function()
  child.lua([[
    _G.mock_treesitter.query_available = false

    local root_node = create_mock_node("chunk", 0, 0, 2, 3)
    local target_node = create_mock_node("function_definition", 0, 0, 2, 3, root_node)
    root_node.named_descendant_for_range = function(self, sr, sc, er, ec)
      return target_node
    end

    _G.mock_treesitter.trees = { create_mock_tree(root_node) }

    local bufnr = create_test_buffer({"function test()", "  return 42", "end"}, "lua")
    local result = CodeExtractor.get_block_with_locals(bufnr, 1, 0)

    _G.test_result = {
      result_type = result and result:type() or nil
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("function_definition", result.result_type)
end

T["get_block_with_locals"]["finds best scope containing target node"] = function()
  child.lua([[
    local root_node = create_mock_node("chunk", 0, 0, 10, 0)
    local target_node = create_mock_node("identifier", 2, 2, 2, 10, root_node)
    local function_node = create_mock_node("function_definition", 1, 0, 5, 3, root_node)
    local class_node = create_mock_node("class_definition", 0, 0, 8, 3, root_node)

    root_node.named_descendant_for_range = function(self, sr, sc, er, ec)
      return target_node
    end

    _G.mock_treesitter.trees = { create_mock_tree(root_node) }
    _G.mock_treesitter.query_captures = {
      { id = 1, node = function_node, meta = {} },
      { id = 1, node = class_node, meta = {} }
    }

    local bufnr = create_test_buffer({
      "class TestClass:",
      "  def test_function():",
      "    test_var = 42",
      "    return test_var",
      "  end",
      "end"
    }, "lua")

    local result = CodeExtractor.get_block_with_locals(bufnr, 2, 2)

    _G.test_result = {
      result_type = result and result:type() or nil
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("function_definition", result.result_type) -- Should prefer smaller scope (function over class)
end

T["get_block_with_locals"]["walks up tree to find significant enclosing block"] = function()
  child.lua([[
    local root_node = create_mock_node("chunk", 0, 0, 5, 0)
    local function_node = create_mock_node("function_definition", 1, 0, 4, 3, root_node)
    local target_node = create_mock_node("identifier", 2, 2, 2, 10, function_node)

    root_node.named_descendant_for_range = function(self, sr, sc, er, ec)
      return target_node
    end

    _G.mock_treesitter.trees = { create_mock_tree(root_node) }
    _G.mock_treesitter.query_captures = {} -- No scopes found

    local bufnr = create_test_buffer({
      "function test()",
      "  local var = 42",
      "  return var",
      "end"
    }, "lua")

    local result = CodeExtractor.get_block_with_locals(bufnr, 2, 2)

    _G.test_result = {
      result_type = result and result:type() or nil
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("function_definition", result.result_type)
end

T["get_block_with_locals"]["returns target node when no significant block found"] = function()
  child.lua([[
    local root_node = create_mock_node("chunk", 0, 0, 3, 0)
    local target_node = create_mock_node("identifier", 1, 0, 1, 5, root_node)

    root_node.named_descendant_for_range = function(self, sr, sc, er, ec)
      return target_node
    end

    _G.mock_treesitter.trees = { create_mock_tree(root_node) }
    _G.mock_treesitter.query_captures = {} -- No scopes found

    local bufnr = create_test_buffer({"local var = 42", "print(var)"}, "lua")
    local result = CodeExtractor.get_block_with_locals(bufnr, 1, 0)

    _G.test_result = {
      result_type = result and result:type() or nil
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("identifier", result.result_type)
end

T["extract_node_data"] = new_set()

T["extract_node_data"]["extracts code block from node successfully"] = function()
  child.lua([[
    local node = create_mock_node("function_definition", 0, 0, 2, 3)
    local bufnr = create_test_buffer({
      "function test()",
      "  return 42",
      "end"
    }, "lua")

    -- Set buffer name for testing
    vim.api.nvim_buf_set_name(bufnr, "/test/project/test.lua")

    local result = CodeExtractor.extract_node_data(bufnr, node)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.eq("function test()\n  return 42\nend", result.data.code_block)
  h.eq(1, result.data.start_line) -- 1-indexed
  h.eq(3, result.data.end_line) -- 1-indexed
  h.eq("lua", result.data.filetype)
  h.expect_contains("test.lua", result.data.filename)
end

T["extract_node_data"]["handles empty lines"] = function()
  child.lua([[
    local node = create_mock_node("function_definition", 0, 0, 0, 0) -- Empty range
    local bufnr = create_test_buffer({""}, "lua")

    local result = CodeExtractor.extract_node_data(bufnr, node)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.eq("", result.data.code_block)
end

T["extract_node_data"]["handles invalid buffer"] = function()
  child.lua([[
    local node = create_mock_node("function_definition", 0, 0, 2, 3)
    local invalid_bufnr = 9999 -- Non-existent buffer

    local result = CodeExtractor.extract_node_data(invalid_bufnr, node)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("error", result.status)
  h.expect_contains("empty", result.data)
end

T["get_fallback_code_block"] = new_set()

T["get_fallback_code_block"]["extracts indentation-based code block"] = function()
  child.lua([[
    local bufnr = create_test_buffer({
      "function test()",
      "  local var = 42",
      "  if var > 0 then",
      "    print(var)",
      "  end",
      "  return var",
      "end",
      "",
      "function other()",
      "  return 0",
      "end"
    }, "lua")

    vim.api.nvim_buf_set_name(bufnr, "/test/project/test.lua")

    -- Extract block at line 3 (inside the if statement)
    local result = CodeExtractor.get_fallback_code_block(bufnr, 3, 4)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.not_eq(nil, result.data.code_block)
  h.eq("lua", result.data.filetype)
  h.expect_contains("test.lua", result.data.filename)
end

T["get_fallback_code_block"]["handles line with no text"] = function()
  child.lua([[
    local bufnr = create_test_buffer({""}, "lua")

    local result = CodeExtractor.get_fallback_code_block(bufnr, 1, 0) -- Row 1 doesn't exist (0-indexed)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("error", result.status)
  h.expect_contains("No text at specified position", result.data)
end

T["get_fallback_code_block"]["respects max block scan lines"] = function()
  child.lua([[
    -- Create a buffer with many lines of same indentation
    local lines = {}
    for i = 1, 150 do
      lines[i] = "  line " .. i
    end
    local bufnr = create_test_buffer(lines, "lua")

    local result = CodeExtractor.get_fallback_code_block(bufnr, 10, 2)

    _G.test_result = {
      status = result.status,
      line_count = result.data and (result.data.end_line - result.data.start_line + 1) or 0,
      start_line = result.data and result.data.start_line or 0,
      end_line = result.data and result.data.end_line or 0
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  -- The scan should be limited by MAX_BLOCK_SCAN_LINES (100) from the starting position
  -- Starting at line 10 (0-indexed), it should scan at most 100 lines forward
  h.expect_truthy(result.end_line <= 111) -- 10 + 100 + 1 for 1-indexed
end

T["get_fallback_code_block"]["handles comments and empty lines"] = function()
  child.lua([[
    local bufnr = create_test_buffer({
      "-- This is a comment",
      "function test()",
      "  -- Another comment",
      "  local var = 42",
      "",
      "  return var",
      "end"
    }, "lua")

    local result = CodeExtractor.get_fallback_code_block(bufnr, 3, 2)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.not_eq(nil, result.data.code_block)
end

T["get_code_block_at_position"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_treesitter()]])
    end,
  },
})

T["get_code_block_at_position"]["returns error for invalid buffer"] = function()
  child.lua([[
    local result = CodeExtractor.get_code_block_at_position(9999, 0, 0)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("error", result.status)
  h.expect_contains("Invalid buffer id", result.data)
end

T["get_code_block_at_position"]["uses treesitter when available"] = function()
  child.lua([[
    local root_node = create_mock_node("chunk", 0, 0, 2, 3)
    local function_node = create_mock_node("function_definition", 0, 0, 2, 3, root_node)

    root_node.named_descendant_for_range = function(self, sr, sc, er, ec)
      return function_node
    end

    _G.mock_treesitter.trees = { create_mock_tree(root_node) }

    local bufnr = create_test_buffer({
      "function test()",
      "  return 42",
      "end"
    }, "lua")

    vim.api.nvim_buf_set_name(bufnr, "/test/project/test.lua")

    local result = CodeExtractor.get_code_block_at_position(bufnr, 1, 0)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.eq("function test()\n  return 42\nend", result.data.code_block)
  h.eq(1, result.data.start_line)
  h.eq(3, result.data.end_line)
end

T["get_code_block_at_position"]["falls back when treesitter fails"] = function()
  child.lua([[
    _G.mock_treesitter.parser_available = false -- Make treesitter fail

    local bufnr = create_test_buffer({
      "function test()",
      "  return 42",
      "end"
    }, "lua")

    vim.api.nvim_buf_set_name(bufnr, "/test/project/test.lua")

    local result = CodeExtractor.get_code_block_at_position(bufnr, 1, 0)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.not_eq(nil, result.data.code_block)
  h.eq("lua", result.data.filetype)
end

T["get_code_block_at_position"]["handles treesitter returning nil node"] = function()
  child.lua([[
    local root_node = create_mock_node("chunk", 0, 0, 2, 3)
    root_node.named_descendant_for_range = function(self, sr, sc, er, ec)
      return nil -- No node found at position
    end

    _G.mock_treesitter.trees = { create_mock_tree(root_node) }

    local bufnr = create_test_buffer({
      "function test()",
      "  return 42",
      "end"
    }, "lua")

    vim.api.nvim_buf_set_name(bufnr, "/test/project/test.lua")

    local result = CodeExtractor.get_code_block_at_position(bufnr, 1, 0)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status) -- Should fall back to indentation-based extraction
  h.not_eq(nil, result.data.code_block)
end

T["get_code_block_at_position"]["preserves file metadata"] = function()
  child.lua([[
    local root_node = create_mock_node("chunk", 0, 0, 2, 3)
    local function_node = create_mock_node("function_definition", 0, 0, 2, 3, root_node)

    root_node.named_descendant_for_range = function(self, sr, sc, er, ec)
      return function_node
    end

    _G.mock_treesitter.trees = { create_mock_tree(root_node) }

    local bufnr = create_test_buffer({
      "function test()",
      "  return 42",
      "end"
    }, "python") -- Different filetype

    vim.api.nvim_buf_set_name(bufnr, "/very/long/path/to/project/src/main.py")

    local result = CodeExtractor.get_code_block_at_position(bufnr, 1, 0)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.eq("python", result.data.filetype)
  h.expect_contains("main.py", result.data.filename)
  -- Should be relative path
  h.expect_truthy(not result.data.filename:match("^/very/long/path"))
end

return T
