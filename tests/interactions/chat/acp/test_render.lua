local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        _G.chat = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["ACP Render"] = new_set()

T["ACP Render"]["restores an agent reply with the buffer ready for input"] = function()
  local result = child.lua([[
    require("codecompanion.interactions.chat.acp.render").restore_session(_G.chat, {
      { sessionUpdate = "user_message_chunk", content = { type = "text", text = "hello" } },
      { sessionUpdate = "agent_message_chunk", content = { type = "text", text = "hi there" } },
    })
    vim.wait(100, function() return false end)

    local lines = h.get_buf_lines(_G.chat.bufnr)
    return {
      modifiable = vim.bo[_G.chat.bufnr].modifiable,
      lines = lines,
    }
  ]])

  h.eq(true, result.modifiable)
  h.eq("hi there", result.lines[#result.lines - 4])
  h.eq("## foo", result.lines[#result.lines - 2])
  h.eq("", result.lines[#result.lines])
end

return T
