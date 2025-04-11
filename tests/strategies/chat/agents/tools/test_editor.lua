local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[_G.chat, _G.agent = require("tests.helpers").setup_chat_buffer()]])

      -- Setup the buffer
      child.lua([[
      local bufnr = vim.api.nvim_create_buf(false, true)
      _G.bufnr = bufnr
      vim.bo[bufnr].readonly = false
      vim.bo[bufnr].buftype = "nofile"

      local lines = {
        "function foo()",
        '    return "foo"',
        "end",
        "",
        "function bar()",
        '    return "bar"',
        "end",
        "",
        "function baz()",
        '    return "baz"',
        "end",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

      return bufnr
  ]])
    end,
    post_case = function()
      _G.bufnr = nil
    end,
    post_once = child.stop,
  },
})

T["editor tool"] = function()
  child.lua([[
    local tool = {
      {
        name = "editor",
        arguments = {
          action = "delete",
          buffer = _G.bufnr,
          start_line = 1,
          end_line = 4,
        }
      },
      {
        name = "editor",
        arguments = {
          action = "add",
          buffer = _G.bufnr,
          code = "function hello_world()\n  return \"Hello, World!\"\nend\n",
          start_line = 1,
        }
      },
      {
        name = "editor",
        arguments = {
          action = "update",
          buffer = _G.bufnr,
          code = "function hello_oli()\n  return \"Hello, Oli!\"\nend",
          start_line = 5,
          end_line = 7,
        }
      },
    }
    agent:execute(chat, tool)
    vim.cmd("buffer " .. _G.bufnr)
  ]])

  expect.reference_screenshot(child.get_screenshot())
end

return T
