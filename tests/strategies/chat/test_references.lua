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
  -- First add a reference and a message that uses it
  chat.References:add({
    source = "test",
    name = "test",
    id = "<buf>test.lua</buf>",
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
      content = "Message without reference",
      opts = {},
    },
  }

  -- Store initial message count
  local initial_count = #chat.messages
  h.eq(initial_count, 2, "Should start with 2 messages")
  h.eq(vim.tbl_count(chat.refs), 1, "Should have 1 reference")

  -- Mock the get_from_chat method to return empty refs
  chat.References.get_from_chat = function()
    return {}
  end

  -- Run the check_references function
  chat:check_references()

  -- Verify results
  h.eq(#chat.messages, 1, "Should have 1 message after reference removal")
  h.eq(chat.messages[1].content, "Message without reference", "Message without reference should remain")
  h.eq(vim.tbl_count(chat.refs), 0, "Should have 0 references")

  -- Verify the message with reference was removed
  local has_ref_message = vim.iter(chat.messages):any(function(msg)
    return msg.opts.reference == "<buf>test.lua</buf>"
  end)

  h.eq(has_ref_message, false, "Message with removed reference should be gone")
end

return T
