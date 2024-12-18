local new_set = MiniTest.new_set
local h = require("tests.helpers")

local T = MiniTest.new_set()

local chat

T["References"] = new_set({
  hooks = {
    pre_case = function()
      chat, _ = h.setup_chat_buffer()
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["References"]["Can be added to the UI of the chat buffer"] = function()
  chat.References:add({
    source = "test",
    name = "test",
    id = "testing",
  })
  chat.References:add({
    source = "test",
    name = "test",
    id = "testing again",
  })

  chat:submit()

  local buffer = h.get_buf_lines(chat.bufnr)
  h.eq("> Sharing:", buffer[3])
  h.eq("> - testing", buffer[4])
  h.eq("> - testing again", buffer[5])
end

T["References"]["Can be deleted"] = function()
  -- Add references
  chat.References:add({
    source = "test",
    name = "test",
    id = "<buf>test.lua</buf>",
  })
  chat.References:add({
    source = "test",
    name = "test2",
    id = "<buf>test2.lua</buf>",
  })

  -- Add messages with and without references
  chat.messages = {
    {
      role = "user",
      content = "Message with reference",
      opts = {
        reference = "<buf>test.lua</buf>",
      },
    },
    {
      role = "user",
      content = "Message with another reference",
      opts = {
        reference = "<buf>test2.lua</buf>",
      },
    },

    {
      role = "user",
      content = "Message without reference",
      opts = {},
    },
  }

  local initial_count = #chat.messages
  h.eq(initial_count, 3, "Should start with 3 messages")
  h.eq(vim.tbl_count(chat.refs), 2, "Should have 2 reference")

  -- Mock the get_from_chat method
  chat.References.get_from_chat = function()
    return { "<buf>test2.lua</buf>" }
  end

  chat:check_references()

  -- Verify results
  h.eq(#chat.messages, 2, "Should have 1 messages after reference removal")
  h.eq(chat.messages[1].content, "Message with another reference")
  h.eq(chat.messages[2].content, "Message without reference")
  h.eq(vim.tbl_count(chat.refs), 1, "Should have 1 reference")

  -- Verify the message with reference was removed
  local has_ref_message = vim.iter(chat.messages):any(function(msg)
    return msg.opts.reference == "<buf>test.lua</buf>"
  end)
  h.eq(has_ref_message, false, "Message with first reference should be gone")

  has_ref_message = vim.iter(chat.messages):any(function(msg)
    return msg.opts.reference == "<buf>test2.lua</buf>"
  end)
  h.eq(has_ref_message, true, "Message with second reference should still be present")
end

return T
