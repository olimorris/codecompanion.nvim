local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()
T["Tools"] = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        h = require('tests.helpers')
        _G.chat = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["Tools"][""] = function()
  child.lua([[
    _G.chat:add_buf_message({ role = "user", content = "Hello World" })
  ]])

  local buffer = child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])
  h.eq({ "## foo", "", "Hello World" }, buffer)

  child.lua_get([[h.send_to_llm(_G.chat, "Hello there")]])
  buffer = child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])

  h.eq("Hello there", buffer[#buffer - 4])
  h.eq("## foo", buffer[#buffer - 2])
  h.eq("", buffer[#buffer])
end

return T
