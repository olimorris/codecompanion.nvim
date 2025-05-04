local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.o.statusline = ""
      child.o.laststatus = 0
      child.lua([[
        codecompanion = require("codecompanion")
        h = require('tests.helpers')
        config = require("tests.config")
        _G.chat, _G.agent = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["References"] = new_set()

T["References"]["Can be added to the UI of the chat buffer"] = function()
  child.lua([[
    _G.chat.references:add({
      source = "test",
      name = "test",
      id = "testing",
    })
    _G.chat.references:add({
      source = "test",
      name = "test",
      id = "testing again",
    })

    _G.chat:submit()
  ]])

  local lines = child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])
  h.eq("> Context:", lines[3])
  h.eq("> - testing", lines[4])
  h.eq("> - testing again", lines[5])
end

T["References"]["Can be deleted"] = function()
  child.lua([[
    -- Add references
    _G.chat.references:add({
      source = "test",
      name = "test",
      id = "<buf>test.lua</buf>",
    })
    _G.chat.references:add({
      source = "test",
      name = "test2",
      id = "<buf>test2.lua</buf>",
    })

    -- Add messages with and without references
    _G.chat.messages = {
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
  ]])

  local initial_count = child.lua_get([[#_G.chat.messages]])
  h.eq(initial_count, 3, "Should start with 3 messages")

  local refs = child.lua_get([[_G.chat.refs]])
  h.eq(vim.tbl_count(refs), 2, "Should have 2 reference")

  -- Mock the get_from_chat method
  child.lua([[
    _G.chat.references.get_from_chat = function()
      return { "<buf>test2.lua</buf>" }
    end

    _G.chat:check_references()
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  -- Verify results
  h.eq(#messages, 2, "Should have 2 messages after reference deleted")
  h.eq(messages[1].content, "Message with another reference")
  h.eq(messages[2].content, "Message without reference")

  refs = child.lua_get([[_G.chat.refs]])
  h.eq(vim.tbl_count(refs), 1, "Should now only have 1 reference")

  -- Verify the message with reference was removed
  local has_ref_message = vim.iter(messages):any(function(msg)
    return msg.opts.reference == "<buf>test.lua</buf>"
  end)
  h.eq(has_ref_message, false, "Message with first reference should be gone")

  has_ref_message = vim.iter(messages):any(function(msg)
    return msg.opts.reference == "<buf>test2.lua</buf>"
  end)
  h.eq(has_ref_message, true, "Message with second reference should still be present")
end

T["References"]["Tools and their schema can be deleted"] = function()
  -- Add messages
  child.lua([[
    _G.chat:add_buf_message({
      role = "user",
      content = "Whats the @weather like in London? Also adding a @func tool too.",
    })
  ]])

  h.eq(1, child.lua_get([[#_G.chat.messages]]), "Should start with the system prompt")
  h.eq(0, vim.tbl_count(child.lua_get([[_G.chat.refs]])), "Should have 0 references")

  child.lua([[
    _G.chat:submit()
  ]])

  h.eq(2, vim.tbl_count(child.lua_get([[_G.chat.refs]])), "Should have 2 reference")
  h.expect_tbl_contains("<tool>weather</tool>", child.lua_get([[_G.chat.tools.schemas]]))
  h.expect_tbl_contains("<tool>func</tool>", child.lua_get([[_G.chat.tools.schemas]]))

  -- Mock the get_from_chat method to pretend that the user has deleted the weather tool
  child.lua([[
    _G.chat.references.get_from_chat = function()
      return { "<tool>func</tool>" }
    end
    _G.chat:check_references()
  ]])

  h.eq({ { "<tool>func</tool>", {
    name = "func",
  } } }, child.lua_get([[chat.tools.schemas]]))
end

T["References"]["Can be pinned"] = function()
  child.lua([[
    _G.chat.references:add({
      id = "<buf>pinned example</buf>",
      path = "tests.stubs.file.txt",
      source = "tests.strategies.chat.slash_commands.basic",
      opts = {
        pinned = true,
      },
    })
    _G.chat.references:add({
      id = "<buf>unpinned example</buf>",
      path = "test2",
      source = "test",
    })

    -- Add messages with and without pins
    _G.chat.messages = {
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
    }
    _G.chat:add_buf_message({
      role = "user",
      content = "What do these references do?",
    })
  ]])

  h.eq(child.lua_get([[#_G.chat.refs]]), 2, "There are two references")
  h.eq(child.lua_get([[#_G.chat.messages]]), 2, "There are three messages")
  h.eq(child.lua_get([[_G.chat.refs[1].opts.pinned]]), true, "Reference is pinned")

  child.lua([[
    -- Mock the submit
    _G.chat:add_buf_message({
      role = "llm",
      content = "Ooooh. I'm not sure. They probably do a lot!",
    })
    _G.chat:submit()
    _G.chat.status = "success"
    _G.chat:done({ content = "This is a mocked response" })
  ]])

  h.eq(child.lua_get([[#_G.chat.messages]]), 4, "There are four messages")
  h.eq(child.lua_get([[_G.chat.messages[#_G.chat.messages].content]]), "Basic Slash Command")

  local buffer = child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])

  h.eq("> Context:", buffer[15])
  h.eq(
    string.format("> - %s<buf>pinned example</buf>", child.lua_get([[config.display.chat.icons.pinned_buffer]])),
    buffer[16]
  )
  h.eq("> - <buf>unpinned example</buf>", buffer[17])

  h.eq({
    {
      id = "<buf>pinned example</buf>",
      opts = {
        pinned = true,
        visible = true,
        watched = false,
      },
      path = "tests.stubs.file.txt",
      source = "tests.strategies.chat.slash_commands.basic",
    },
    {
      id = "<buf>unpinned example</buf>",
      opts = {
        pinned = false,
        visible = true,
        watched = false,
      },
      path = "test2",
      source = "test",
    },
  }, child.lua_get([[_G.chat.refs]]), "References are correct")
end

T["References"]["Tree-sitter test"] = function()
  child.lua([[
    _G.chat.references:add({
      id = "<buf>pinned example</buf>",
      path = "tests.stubs.file.txt",
      source = "tests.strategies.chat.slash_commands.basic",
      opts = {
        pinned = true,
      },
    })
  ]])

  h.eq({ "<buf>pinned example</buf>" }, child.lua_get([[_G.chat.references:get_from_chat()]]))
end

T["References"]["Render"] = function()
  child.lua([[
    _G.chat.refs = {
      {
        id = "<buf>pinned example</buf>",
        path = "tests.stubs.file.txt",
        source = "tests.strategies.chat.slash_commands.basic",
        opts = {
          pinned = true,
        },
      },
    }
    _G.chat.references:render()
  ]])

  h.eq(
    { "## foo", "", "> Context:", "> -  <buf>pinned example</buf>", "", "" },
    child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])
  )
end

T["References"]["Render invisible"] = function()
  child.lua([[
    _G.chat.refs = {
      {
        id = "<buf>pinned example</buf>",
        path = "tests.stubs.file.txt",
        source = "tests.strategies.chat.slash_commands.basic",
        opts = {
          visible = false,
          pinned = true,
        },
      },
    }
    _G.chat.references:render()
  ]])

  h.eq({ "## foo", "", "" }, child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]]))
end

T["References"]["can be cleared from messages"] = function()
  child.lua([[
    _G.chat.references:add({
      id = "<buf>pinned example</buf>",
      path = "tests.stubs.file.txt",
      source = "tests.strategies.chat.slash_commands.basic",
      opts = {
        pinned = true,
      },
    })
  ]])

  local content = child.lua([[
    local message = {
      role = "user",
      content = "> Context:\n> -  <buf>pinned example</buf>\n\nHello, World",
    }
    return _G.chat.references:clear(message).content
  ]])

  h.eq("Hello, World", content)
end

---Bug fix: #889 https://github.com/olimorris/codecompanion.nvim/issues/889
---We want to use relative paths as they're prettier in the chat buffer than
---full paths. However, a lot of the providers only output the full path
T["References"]["file references always have a relative id"] = function()
  child.lua([[
    local path = vim.fn.fnamemodify(vim.fn.getcwd(), ":p") .. "tests/stubs/file.txt"
    _G.chat.references:add({
      id = "<file>tests/stubs/file.txt</file>",
      path = path,
      source = "codecompanion.strategies.chat.slash_commands.file",
      opts = {
        pinned = true,
      },
    })
    _G.chat:add_buf_message({ role = "user", content = "Can you see the updated content?" })
    _G.chat:submit()
  ]])

  h.expect_starts_with("Here is the updated content", child.lua_get([[_G.chat.messages[#_G.chat.messages].content]]))
  h.eq("<file>tests/stubs/file.txt</file>", child.lua_get([[_G.chat.messages[#_G.chat.messages].opts.reference]]))
end

return T
