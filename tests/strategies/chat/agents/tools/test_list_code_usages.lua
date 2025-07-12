local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Setup test directory structure
        _G.TEST_DIR = 'tests/stubs/list_code_usages'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(vim.fn.tempname(), _G.TEST_DIR)

        -- Create test directory structure and test file
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/src', 'p')

        local test_file = {
          path = 'src/test_symbols.lua',
          content = {
            '-- Test symbols for list_code_usages tool',
            'local M = {}',
            '',
            'function M.testFunction(arg1, arg2)',
            '  return arg1 + arg2',
            'end',
            '',
            'M.testVariable = "test value"',
            '',
            'return M'
          }
        }

        local filepath = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, test_file.path)
        vim.fn.writefile(test_file.content, filepath)

        -- Load the test file into a buffer
        vim.cmd('edit ' .. filepath)
        _G.test_bufnr = vim.api.nvim_get_current_buf()

        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

        -- Change to test directory
        vim.cmd('cd ' .. _G.TEST_DIR_ABSOLUTE)
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
        vim.fn.delete(_G.TEST_DIR_ABSOLUTE, 'rf')
      ]])
    end,
    post_once = child.stop,
  },
})

T["filepaths can be empty"] = function()
  child.lua([[
    chat. context = {
      winnr = 0
    }
    local tool = {
      {
        ["function"] = {
          name = "list_code_usages",
          arguments = '{ "symbolName": "testFunction", "filepaths": "" }'
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("references of symbol: `testFunction`", output)
end

T["validates symbol parameter"] = function()
  child.lua([[
    chat. context = {
      winnr = 0
    }
    local tool = {
      {
        ["function"] = {
          name = "list_code_usages",
          arguments = '{ "symbolName": ""}'
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("Symbol name is required and cannot be empty.", output)
end

T["handles symbol not found"] = function()
  child.lua([[
    chat. context = {
      winnr = 0
    }
    local tool = {
      {
        ["function"] = {
          name = "list_code_usages",
          arguments = '{ "symbolName": "nonExistentSymbol" }'
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("Symbol not found in workspace", output)
end

return T
