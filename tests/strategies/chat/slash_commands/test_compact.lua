local config = require("tests.config")
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua([[
        h = require('tests.helpers')
        _G.chat, _ = h.setup_chat_buffer()

        _G.chat.messages = {
          { role = "system", content = "You are a helpful assistant." },
          { role = "user", content = "Some file share", _meta = { tag = "file" } },
          { role = "user", content = "Hello!" },
          { role = "assistant", content = "Hi there! How can I assist you today?" },
          { role = "user", content = "Can you help me with Lua?" },
          { role = "llm", content = "Sure! What do you need help with?" },
        }

        _G.compact = require("codecompanion.strategies.chat.slash_commands.catalog.compact").new({
          Chat = chat,
          context = {},
          opts = {},
        })
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Compact"] = new_set()

T["Compact"]["Creates conversations from a chat buffer"] = function()
  local result = child.lua([[
    return _G.compact:create_conversation(_G.chat.messages)
  ]])

  h.eq(
    table.concat({
      '<message role="user">Some file share</message>',
      '<message role="user">Hello!</message>',
      '<message role="assistant">Hi there! How can I assist you today?</message>',
      '<message role="user">Can you help me with Lua?</message>',
    }),
    result
  )
end

T["Compact"]["compacts chat messages"] = function()
  local result = child.lua([[
    _G.compact:compact_messages()
    return _G.chat.messages
  ]])

  local messages = vim.tbl_map(function(msg)
    return msg.content
  end, result)

  h.eq({ "You are a helpful assistant.", "Some file share" }, messages)
end

return T
