local h = require("tests.helpers")

local new_set = MiniTest.new_set

local bufnr

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[vim.g.codecompanion_auto_tool_mode = true]])
      child.lua([[_G.chat, _G.agent = require("tests.helpers").setup_chat_buffer()]])

      -- Setup the buffer
      bufnr = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    _G.bufnr = bufnr
    vim.bo[bufnr].readonly = false

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
      _G.xml = nil
    end,
    post_once = child.stop,
  },
})

T["editor tool"] = function()
  child.lua([[
    --require("tests.log")
    local tool = {
      [0] = {
        name = "editor",
        arguments = string.format('{"action": "update", "buffer": %s, "code": "function hello_world()\\n  return \\"Hello, World!\\"\\nend", "start_line": 1, "end_line": 3}', _G.bufnr),
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("vim.api.nvim_buf_get_lines(_G.bufnr, 0, -1, true)")
  h.eq("function hello_world()", output[1])
end

return T
