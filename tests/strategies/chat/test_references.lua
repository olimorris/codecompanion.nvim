local config = require("codecompanion.config")

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
  chat.references:add({
    source = "test",
    name = "test",
    id = "testing",
  })
  chat.references:add({
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
  chat.references:add({
    source = "test",
    name = "test",
    id = "<buf>test.lua</buf>",
  })
  chat.references:add({
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
  chat.references.get_from_chat = function()
    return { "<buf>test2.lua</buf>" }
  end

  chat:check_references()

  -- Verify results
  h.eq(#chat.messages, 2, "Should have 2 messages after reference removal")
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

T["References"]["Can be pinned"] = function()
  local icon = config.display.chat.icons.pinned_buffer

  chat.references:add({
    id = "<buf>pinned example</buf>",
    path = "tests.stubs.file.txt",
    source = "tests.strategies.chat.slash_commands.basic",
    opts = {
      pinned = true,
    },
  })
  chat.references:add({
    id = "<buf>unpinned example</buf>",
    path = "test2",
    source = "test",
  })

  -- Add messages with and without pins
  chat.messages = {
    {
      role = "user",
      content = "Pinned reference",
      opts = {
        reference = "<buf>pinned example</buf>",
      },
    },
    {
      role = "user",
      content = "Unpinned reference",
      opts = {
        reference = "<buf>unpinned example</buf>",
      },
    },
    {
      role = "user",
      content = "What do these references do?",
    },
  }
  h.eq(#chat.refs, 2, "There are two references")
  h.eq(#chat.messages, 3, "There are three messages")
  h.eq(chat.refs[1].opts.pinned, true, "Reference is pinned")

  chat:submit()
  h.eq(#chat.messages, 5, "There are four messages")
  h.eq(chat.messages[#chat.messages].content, "Basic Slash Command")

  chat:done({})

  local buffer = h.get_buf_lines(chat.bufnr)
  h.eq("> Sharing:", buffer[3])
  h.eq(string.format("> - %s<buf>pinned example</buf>", icon), buffer[8])
  h.eq("> - <buf>unpinned example</buf>", buffer[9])

  h.eq(chat.refs, {
    {
      id = "<buf>pinned example</buf>",
      opts = {
        pinned = true,
        watched = false,
      },
      path = "tests.stubs.file.txt",
      source = "tests.strategies.chat.slash_commands.basic",
    },
    {
      id = "<buf>unpinned example</buf>",
      opts = {
        pinned = false,
        watched = false,
      },
      path = "test2",
      source = "test",
    },
  })
end

T["References"]["Tree-sitter test"] = function()
  chat.references:add({
    id = "<buf>pinned example</buf>",
    path = "tests.stubs.file.txt",
    source = "tests.strategies.chat.slash_commands.basic",
    opts = {
      pinned = true,
    },
  })

  h.eq(chat.references:get_from_chat(), { "<buf>pinned example</buf>" })
end

T["References"]["Render"] = function()
  chat.refs = {
    {
      id = "<buf>pinned example</buf>",
      path = "tests.stubs.file.txt",
      source = "tests.strategies.chat.slash_commands.basic",
      opts = {
        pinned = true,
      },
    },
  }
  chat.references:render()

  h.eq(h.get_buf_lines(chat.bufnr), { "## foo", "", "> Sharing:", "> -  <buf>pinned example</buf>", "", "" })
end

T["References"]["can be cleared from messages"] = function()
  chat.references:add({
    id = "<buf>pinned example</buf>",
    path = "tests.stubs.file.txt",
    source = "tests.strategies.chat.slash_commands.basic",
    opts = {
      pinned = true,
    },
  })

  local message = {
    role = "user",
    content = "> Sharing:\n> -  <buf>pinned example</buf>\n\nHello, World",
  }

  h.eq("Hello, World", chat.references:clear(message).content)
end

return T
