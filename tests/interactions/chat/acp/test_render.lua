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
    -- A streamed chunk left in the queue is flushed on a timer, which locks the buffer
    vim.wait(1000, function() return _G.chat.builder._queue == nil end)

    return {
      modifiable = vim.bo[_G.chat.bufnr].modifiable,
      lines = h.get_buf_lines(_G.chat.bufnr),
    }
  ]])

  h.eq(true, result.modifiable)
  h.eq({ "## foo", "", "hello", "", "## assistant", "", "hi there", "", "## foo", "", "" }, result.lines)
end

return T
