local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      child.lua([[
        h = require("tests.helpers")
        _G.helpers = require("codecompanion.strategies.chat.helpers")
        -- Create temporary directory for test files
        _G.TEST_DIR = "tests/stubs/helpers"
        _G.TEMP_DIR = vim.fs.joinpath(vim.fn.tempname(), _G.TEST_DIR)
        vim.fn.mkdir(_G.TEMP_DIR, "p")

        -- Helper function to create test files in temp directory
        function _G.create_test_files()
          -- Lua file with functions
          vim.fn.writefile({
            "local M = {}",
            "",
            "function M.public_function()",
            "  return 'hello'",
            "end",
            "",
            "local function private_function()",
            "  local x = 1",
            "  return x",
            "end",
            "",
            "return M",
          }, vim.fs.joinpath(_G.TEMP_DIR, "test_symbols.lua"))

          -- Python file
          vim.fn.writefile({
            "class MyClass:",
            "    def __init__(self):",
            "        self.value = 0",
            "",
            "    def instance_method(self):",
            "        return self.value",
            "",
            "def global_function():",
            "    print('hello')",
            "",
            "def another_function(param):",
            "    return param * 2",
          }, vim.fs.joinpath(_G.TEMP_DIR, "test_symbols.py"))

          -- Empty file
          vim.fn.writefile({}, vim.fs.joinpath(_G.TEMP_DIR, "empty_file.lua"))

          -- File with no symbols
          vim.fn.writefile({
            "-- Just a comment",
            "local x = 1",
          }, vim.fs.joinpath(_G.TEMP_DIR, "no_symbols.lua"))

          -- Unsupported file type
          vim.fn.writefile({
            "This is just text",
          }, vim.fs.joinpath(_G.TEMP_DIR, "plain.txt"))
        end

        -- Simple helper functions using buffer variables
        function _G.test_symbols(filename)
          local filepath = vim.fs.joinpath(_G.TEMP_DIR, filename)
          local symbols, content = _G.helpers.extract_file_symbols(filepath)
          vim.b.cc_test_symbols = symbols
          return symbols, content
        end

        function _G.test_filtered_symbols(filename, target_kinds)
          local filepath = vim.fs.joinpath(_G.TEMP_DIR, filename)
          local symbols, content = _G.helpers.extract_file_symbols(filepath, target_kinds)
          vim.b.cc_test_symbols = symbols
          return symbols, content
        end

        function _G.get_symbol_names()
          local symbols = vim.b.cc_test_symbols
          local names = {}
          if symbols then
            for _, symbol in ipairs(symbols) do
              table.insert(names, symbol.name)
            end
          end
          return names
        end

        function _G.validate_structure()
          local symbols = vim.b.cc_test_symbols
          if not symbols then
            return false
          end

          for _, symbol in ipairs(symbols) do
            if not symbol.name or not symbol.kind or not symbol.start_line or not symbol.end_line or not symbol.range then
              return false
            end

            local range = symbol.range
            if not range.lnum or not range.end_lnum or not range.col or not range.end_col then
              return false
            end
          end
          return true
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Helpers"] = new_set()
T["Helpers"]["extract_file_symbols"] = new_set()

T["Helpers"]["extract_file_symbols"]["extracts Lua symbols correctly"] = function()
  child.lua([[_G.create_test_files()]])
  local symbols = child.lua_get("_G.test_symbols('test_symbols.lua')")
  h.eq("table", type(symbols))
  h.eq(true, #symbols > 0)
  h.eq(true, child.lua_get("_G.validate_structure()"))
  local symbol_names = child.lua_get("_G.get_symbol_names()")
  h.eq(true, vim.tbl_contains(symbol_names, "M.public_function"))
  h.eq(true, vim.tbl_contains(symbol_names, "private_function"))
end

T["Helpers"]["extract_file_symbols"]["extracts Python symbols correctly"] = function()
  child.lua([[_G.create_test_files()]])
  local symbols = child.lua_get("_G.test_symbols('test_symbols.py')")
  if not symbols then
    return
  end
  h.eq("table", type(symbols))
  h.eq(true, #symbols > 0)
  h.eq(true, child.lua_get("_G.validate_structure()"))
  local symbol_names = child.lua_get("_G.get_symbol_names()")
  h.eq(true, vim.tbl_contains(symbol_names, "MyClass"))
  h.eq(true, vim.tbl_contains(symbol_names, "global_function"))
end

T["Helpers"]["extract_file_symbols"]["filters by target kinds"] = function()
  child.lua([[_G.create_test_files()]])
  local all_symbols = child.lua_get("_G.test_symbols('test_symbols.lua')")
  local filtered_symbols = child.lua_get("_G.test_filtered_symbols('test_symbols.lua', {'Function'})")
  h.eq("table", type(all_symbols))
  h.eq("table", type(filtered_symbols))
  h.eq(true, #filtered_symbols <= #all_symbols)
end

T["Helpers"]["extract_file_symbols"]["handles empty file"] = function()
  child.lua([[_G.create_test_files()]])
  local symbols = child.lua_get("_G.test_symbols('empty_file.lua')")

  h.eq("table", type(symbols))
  h.eq(0, #symbols)
end

T["Helpers"]["extract_file_symbols"]["handles file with no symbols"] = function()
  child.lua([[_G.create_test_files()]])
  local symbols = child.lua_get("_G.test_symbols('no_symbols.lua')")
  h.eq("table", type(symbols))
  h.eq(0, #symbols)
end

T["Helpers"]["extract_file_symbols"]["handles nonexistent file"] = function()
  local symbols = child.lua_get("_G.test_symbols('nonexistent.lua')")
  h.eq(symbols, vim.NIL)
end

return T
