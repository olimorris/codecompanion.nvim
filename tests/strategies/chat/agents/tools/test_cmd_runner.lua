local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

        _G.output = nil
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["cmd_runner tool"] = function()
  child.lua([[
    --require("tests.log")
    local tool = {
      {
        ["function"] = {
          name = "cmd_runner",
          arguments = '{"cmd": "echo hello world"}',
        },
      },
    }
    agent:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, true)")
  h.eq(
    { "## foo", "", "The output from the command `echo hello world`:", "", "```txt", "hello world", "```", "", "" },
    output
  )
end

return T
