local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Setup test directory structure
        _G.TEST_DIR = 'tests/stubs/grep_search'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(vim.fn.tempname(), _G.TEST_DIR)

        -- Create test directory structure
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/src/components', 'p')
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/src/utils', 'p')
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/tests', 'p')
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/docs', 'p')

        -- Create test files with actual content to search
        local test_files = {
          {
            path = 'src/components/Button.js',
            content = {
              'import React from "react";',
              '',
              'function Button({ onClick, children }) {',
              '  return (',
              '    <button className="btn-primary" onClick={onClick}>',
              '      {children}',
              '    </button>',
              '  );',
              '}',
              '',
              'export default Button;'
            }
          },
          {
            path = 'src/components/Modal.ts',
            content = {
              'interface ModalProps {',
              '  isOpen: boolean;',
              '  onClose: () => void;',
              '  children: React.ReactNode;',
              '}',
              '',
              'export function Modal({ isOpen, onClose, children }: ModalProps) {',
              '  if (!isOpen) return null;',
              '',
              '  return (',
              '    <div className="modal-overlay">',
              '      <div className="modal-content">',
              '        <button onClick={onClose}>Close</button>',
              '        {children}',
              '      </div>',
              '    </div>',
              '  );',
              '}'
            }
          },
          {
            path = 'src/utils/helpers.js',
            content = {
              '// Utility functions',
              'export function formatDate(date) {',
              '  return date.toLocaleDateString();',
              '}',
              '',
              'export function debounce(func, delay) {',
              '  let timeoutId;',
              '  return function(...args) {',
              '    clearTimeout(timeoutId);',
              '    timeoutId = setTimeout(() => func.apply(this, args), delay);',
              '  };',
              '}'
            }
          },
          {
            path = 'tests/button.test.js',
            content = {
              'import { render, screen } from "@testing-library/react";',
              'import Button from "../src/components/Button";',
              '',
              'test("renders button with text", () => {',
              '  render(<Button>Click me</Button>);',
              '  const button = screen.getByRole("button");',
              '  expect(button).toBeInTheDocument();',
              '});'
            }
          },
          {
            path = 'package.json',
            content = {
              '{',
              '  "name": "test-project",',
              '  "version": "1.0.0",',
              '  "scripts": {',
              '    "test": "jest",',
              '    "build": "webpack"',
              '  }',
              '}'
            }
          }
        }

        for _, file in ipairs(test_files) do
          local path = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, file.path)
          vim.fn.writefile(file.content, path)
        end

        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        -- Change to test directory for relative path testing
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

T["can find basic text matches"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "grep_search",
          arguments = '{"query": "Button"}'
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")

  -- Should find matches in multiple files
  h.expect_contains("Button.js:3 src/components", output) -- function Button declaration
  h.expect_contains("Button.js:11 src/components", output) -- export default Button
  h.expect_contains("button.test.js:2 tests", output) -- import Button
  h.expect_contains("button.test.js:5 tests", output) -- render(<Button>
end

T["can search for patterns starting with hyphen"] = function()
  -- Create a test file with content starting with hyphen
  child.lua([[
    local test_file_path = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, 'src/utils/config.js')
    local content = {
      '// Configuration file',
      'const config = {',
      '  -debug-mode: true,',
      '  -verbose: false,',
      '  -timeout: 5000',
      '};',
      '',
      'export default config;',
      '',
      '// Another line with -debug-mode',
      'const settings = { -debug-mode: true };'
    }
    vim.fn.writefile(content, test_file_path)
  ]])

  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "grep_search",
          arguments = '{"query": "-debug-mode"}'
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")

  h.expect_contains("config.js:3 src/utils", output) -- -debug-mode: true in config
  h.expect_contains("config.js:10 src/utils", output) -- -debug-mode in comment
  h.expect_contains("config.js:11 src/utils", output) -- -debug-mode in settings
end

return T
