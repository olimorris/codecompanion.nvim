local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
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

T["Context"] = new_set()

T["Context"]["Can be added to the UI of the chat buffer"] = function()
  child.lua([[
    _G.chat.context:add({
      source = "test",
      name = "test",
      id = "testing",
    })
    _G.chat.context:add({
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

T["Context"]["Can be deleted"] = function()
  child.lua([[
    -- Add context_items
    _G.chat.context:add({
      source = "test",
      name = "test",
      id = "<buf>test.lua</buf>",
    })
    _G.chat.context:add({
      source = "test",
      name = "test2",
      id = "<buf>test2.lua</buf>",
    })

    -- Add messages with and without context_items
    _G.chat.messages = {
      {
        role = "user",
        content = "Message with some context",
        opts = {
          context_id = "<buf>test.lua</buf>",
        },
      },
      {
        role = "user",
        content = "Message with some more context",
        opts = {
          context_id = "<buf>test2.lua</buf>",
        },
      },

      {
        role = "user",
        content = "Message without context",
        opts = {},
      },
    }
  ]])

  local initial_count = child.lua_get([[#_G.chat.messages]])
  h.eq(initial_count, 3, "Should start with 3 messages")

  local context_items = child.lua_get([[_G.chat.context_items]])
  h.eq(vim.tbl_count(context_items), 2, "Should have 2 context_items")

  -- Mock the get_from_chat method
  child.lua([[
    _G.chat.context.get_from_chat = function()
      return { "<buf>test2.lua</buf>" }
    end

    _G.chat:check_context()
  ]])

  local messages = child.lua_get([[_G.chat.messages]])

  -- Verify results
  h.eq(#messages, 2, "Should have 2 messages after context is deleted")
  h.eq(messages[1].content, "Message with some more context")
  h.eq(messages[2].content, "Message without context")

  context_items = child.lua_get([[_G.chat.context_items]])
  h.eq(vim.tbl_count(context_items), 1, "Should now only have 1 context item")

  -- Verify the message with context was removed
  local has_context = vim.iter(messages):any(function(msg)
    return msg.opts.context_id == "<buf>test.lua</buf>"
  end)
  h.eq(has_context, false, "Message with first context item should be gone")

  has_context = vim.iter(messages):any(function(msg)
    return msg.opts.context_id == "<buf>test2.lua</buf>"
  end)
  h.eq(has_context, true, "Message with second context item should still be present")
end

T["Context"]["Tools and their schema can be deleted"] = function()
  -- Add messages
  child.lua([[
    _G.chat:add_buf_message({
      role = "user",
      content = "Whats the @{weather} like in London? Also adding a @{func} tool too.",
    })
  ]])

  h.eq(1, child.lua_get([[#_G.chat.messages]]), "Should start with the system prompt")
  h.eq(0, vim.tbl_count(child.lua_get([[_G.chat.context_items]])), "Should have 0 context_items")

  child.lua([[
    _G.chat:submit()
  ]])

  h.eq(2, vim.tbl_count(child.lua_get([[_G.chat.context_items]])), "Should have 2 context items")
  h.expect_tbl_contains("<tool>weather</tool>", child.lua_get([[_G.chat.tools.schemas]]))
  h.expect_tbl_contains("<tool>func</tool>", child.lua_get([[_G.chat.tools.schemas]]))

  -- Mock the get_from_chat method to pretend that the user has deleted the weather tool
  child.lua([[
    _G.chat.context.get_from_chat = function()
      return { "<tool>func</tool>" }
    end
    _G.chat:check_context()
  ]])

  h.eq({
    ["<tool>func</tool>"] = {
      name = "func",
    },
  }, child.lua_get([[chat.tools.schemas]]))
end

T["Context"]["Can be pinned"] = function()
  child.lua([[
     _G.chat.context:add({
       id = "<buf>pinned example</buf>",
       path = "tests.stubs.file.txt",
       source = "tests.strategies.chat.slash_commands.basic",
       opts = {
         pinned = true,
       },
     })
     _G.chat.context:add({
       id = "<buf>unpinned example</buf>",
       path = "test2",
       source = "test",
     })

     -- Add messages with and without pins
     _G.chat.messages = {
       {
         role = "user",
         content = "Pinned context",
         opts = {
           context_id = "<buf>pinned example</buf>",
         },
       },
       {
         role = "user",
         content = "Unpinned context",
         opts = {
           context_id = "<buf>unpinned example</buf>",
         },
       },
     }
     _G.chat:add_buf_message({
       role = "user",
       content = "What do these context_items do?",
     })
   ]])

  h.eq(child.lua_get([[#_G.chat.context_items]]), 2, "There are two context_items")
  h.eq(child.lua_get([[#_G.chat.messages]]), 2, "There are three messages")
  h.eq(child.lua_get([[_G.chat.context_items[1].opts.pinned]]), true, "Context is pinned")

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
    string.format("> - %s<buf>pinned example</buf>", child.lua_get([[config.display.chat.icons.buffer_pin]])),
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
  }, child.lua_get([[_G.chat.context_items]]), "Context are correct")
end

T["Context"]["Tree-sitter test"] = function()
  child.lua([[
     _G.chat.context:add({
       id = "<buf>pinned example</buf>",
       path = "tests.stubs.file.txt",
       source = "tests.strategies.chat.slash_commands.basic",
       opts = {
         pinned = true,
       },
     })
   ]])

  h.eq({ "<buf>pinned example</buf>" }, child.lua_get([[_G.chat.context:get_from_chat()]]))
end

T["Context"]["Render"] = function()
  child.lua([[
     _G.chat.context_items = {
       {
         id = "<buf>pinned example</buf>",
         path = "tests.stubs.file.txt",
         source = "tests.strategies.chat.slash_commands.basic",
         opts = {
           pinned = true,
         },
       },
     }
     _G.chat.context:render()
   ]])

  h.eq(
    { "## foo", "", "> Context:", "> -  <buf>pinned example</buf>", "", "" },
    child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])
  )
end

T["Context"]["Render invisible"] = function()
  child.lua([[
     _G.chat.context_items = {
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
     _G.chat.context:render()
   ]])

  h.eq({ "## foo", "", "" }, child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]]))
end

T["Context"]["can be cleared from messages"] = function()
  child.lua([[
     _G.chat.context:add({
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
     return _G.chat.context:clear(message).content
   ]])

  h.eq("Hello, World", content)
end

---Bug fix: #889 https://github.com/olimorris/codecompanion.nvim/issues/889
---We want to use relative paths as they're prettier in the chat buffer than
---full paths. However, a lot of the providers only output the full path
T["Context"]["file context_items always have a relative id"] = function()
  child.lua([[
     local path = vim.fn.fnamemodify(vim.fn.getcwd(), ":p") .. "tests/stubs/file.txt"
     _G.chat.context:add({
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

  h.expect_starts_with(
    '<attachment filepath="tests/stubs/file.txt">Here is the updated content from the file',
    child.lua_get([[_G.chat.messages[#_G.chat.messages].content]])
  )
  h.eq("<file>tests/stubs/file.txt</file>", child.lua_get([[_G.chat.messages[#_G.chat.messages].opts.context_id]]))
end

T["Context"]["Correctly removes tool schema and usage flag on context deletion"] = function()
  -- 1. Add multiple tools via a message containing agent triggers
  child.lua([[
     -- Add a user message that triggers multiple tool agents
     local message = {
       role = config.constants.USER_ROLE,
       content = "Whats the @{weather} like in London? Also adding a @{func} tool too.",
     }
     _G.chat:add_message(message) -- Add to message history

     -- Simulate the pre-submit processing that adds tools based on agents
     _G.chat:replace_vars_and_tools(message) -- This calls agents:parse -> tools:add
     _G.chat:check_context() -- Sync the context table initially
   ]])

  -- 2. Verify initial state (both tools present)
  local initial_schemas = child.lua_get([[_G.chat.tools.schemas]])
  local initial_context_count = child.lua_get([[#_G.chat.context_items]])
  local initial_in_use = child.lua_get([[_G.chat.tools.in_use]])

  h.eq(2, vim.tbl_count(initial_schemas), "Should have 2 schemas initially")
  h.expect_truthy(initial_schemas["<tool>weather</tool>"], "Weather schema should exist")
  h.expect_truthy(initial_schemas["<tool>func</tool>"], "Func schema should exist")
  h.eq(2, initial_context_count, "Should have 2 context_items initially")
  h.eq({ weather = true, func = true }, initial_in_use, "Both tools should be in use initially")

  -- 3. Simulate deleting the 'weather' tool context by mocking get_from_chat
  child.lua([[
     -- Mock get_from_chat to simulate user deleting the weather tool context from the buffer UI
     _G.chat.context.get_from_chat = function()
       -- This function should return a list of context IDs *currently* found in the buffer
       return { "<tool>func</tool>" } -- Simulate only the func tool context remaining
     end

     -- Run the check_context function which contains the fix
     _G.chat:check_context()
   ]])

  -- 4. Verify final state (only 'func' tool remains)
  local final_schemas = child.lua_get([[_G.chat.tools.schemas]])
  local final_context_count = child.lua_get([[#_G.chat.context_items]])
  local final_in_use = child.lua_get([[_G.chat.tools.in_use]])

  -- Define the expected final state for the schemas map
  -- Only the func schema and still in a map keyed by ID
  local expected_final_schema_map = {
    ["<tool>func</tool>"] = { name = "func" },
  }
  -- Define the expected final state for the in_use table
  local expected_final_in_use = {
    func = true, -- Only func should remain marked as in use
  }

  h.eq(1, vim.tbl_count(final_schemas), "Should have 1 schema after deletion")
  h.eq(expected_final_schema_map, final_schemas, "Schema map should only contain func tool, keyed by ID")
  h.eq(1, final_context_count, "Should have 1 context after deletion")
  h.eq(expected_final_in_use, final_in_use, "Only func tool should be marked in use after deletion")
end

T["Context"]["Show icons immediately when added with default parameters"] = function()
  child.lua([[
     -- Test watched context with default parameters
     _G.chat.context:add({
       id = "<buf>watched_file.lua</buf>",
       path = "test_watched.lua",
       source = "codecompanion.strategies.chat.slash_commands.buffer",
       opts = {
         watched = true,
       },
     })

     -- Test pinned context with default parameters
     _G.chat.context:add({
       id = "<buf>pinned_file.lua</buf>",
       path = "test_pinned.lua",
       source = "codecompanion.strategies.chat.slash_commands.buffer",
       opts = {
         pinned = true,
       },
     })

     -- Test regular context for comparison
     _G.chat.context:add({
       id = "<buf>regular_file.lua</buf>",
       path = "test_regular.lua",
       source = "codecompanion.strategies.chat.slash_commands.buffer",
     })
   ]])

  local lines = child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])

  -- Check that the context header appears
  h.eq("> Context:", lines[3])

  -- Check that watched context shows with icon immediately
  h.eq(
    string.format("> - %s<buf>watched_file.lua</buf>", child.lua_get([[config.display.chat.icons.buffer_watch]])),
    lines[4]
  )

  -- Check that pinned context shows with icon immediately
  h.eq(
    string.format("> - %s<buf>pinned_file.lua</buf>", child.lua_get([[config.display.chat.icons.buffer_pin]])),
    lines[5]
  )

  -- Check that regular context shows without icon
  h.eq("> - <buf>regular_file.lua</buf>", lines[6])
end

T["Context"]["Tool group with collapse_tools shows single group context"] = function()
  child.lua([[
     local message = { role = "user", content = "@{test_group} help" }
     _G.chat:add_message(message)
     _G.chat:replace_vars_and_tools(message)
   ]])

  local context_in_chat = child.lua_get([[_G.chat.context:get_from_chat()]])
  h.expect_tbl_contains("<group>test_group</group>", context_in_chat)

  -- Verify system message was added with group context
  child.lua([[
     _G.system_msg = nil
     for _, msg in ipairs(_G.chat.messages) do
       if msg.role == "system" and msg.opts and msg.opts.context_id == "<group>test_group</group>" then
         _G.system_msg = { content = msg.content, context_id = msg.opts.context_id }
         break
       end
     end
   ]])

  local system_msg = child.lua_get("_G.system_msg")
  h.eq("Test group system prompt", system_msg.content)
  h.eq("<group>test_group</group>", system_msg.context_id)
end

T["Context"]["Tool group without collapse_tools shows individual tools"] = function()
  child.lua([[
     local message = { role = "user", content = "@{test_group2} help" }
     _G.chat:add_message(message)
     _G.chat:replace_vars_and_tools(message)
   ]])

  local context_in_chat = child.lua_get([[_G.chat.context:get_from_chat()]])
  h.expect_tbl_contains("<tool>func</tool>", context_in_chat)
  h.expect_tbl_contains("<tool>weather</tool>", context_in_chat)

  -- Verify system message still has group context even with individual tools
  child.lua([[
     _G.system_msg_content = nil
     for _, msg in ipairs(_G.chat.messages) do
       if msg.role == "system" and msg.opts and msg.opts.context_id == "<group>test_group2</group>" then
         _G.system_msg_content = msg.content
         break
       end
     end
   ]])

  local system_msg = child.lua_get("_G.system_msg_content")
  h.eq("Individual tools system prompt", system_msg)
end

T["Context"]["Removing collapsed group removes all its tools and system message"] = function()
  child.lua([[
     local message = { role = "user", content = "@{remove_group} help" }
     _G.chat:add_message(message)
     _G.chat:replace_vars_and_tools(message)
   ]])

  -- Verify initial state
  child.lua([[
     _G.initial_system_msg_found = false
     for _, msg in ipairs(_G.chat.messages) do
       if msg.role == "system" and msg.opts and msg.opts.context_id == "<group>remove_group</group>" then
         _G.initial_system_msg_found = true
         break
       end
     end
   ]])

  h.eq(true, child.lua_get("_G.initial_system_msg_found"), "System message should exist initially")

  child.lua([[
     -- Mock removing the group context
     _G.chat.context.get_from_chat = function() return {} end
     _G.chat:check_context()
   ]])

  local final_schemas = child.lua_get([[_G.chat.tools.schemas]])
  local final_in_use = child.lua_get([[_G.chat.tools.in_use]])

  h.eq({}, final_schemas, "All tool schemas should be removed")
  h.eq({}, final_in_use, "All tools should be removed from in_use")

  -- Verify system message with group context is removed
  child.lua([[
     _G.system_msg_exists = false
     for _, msg in ipairs(_G.chat.messages) do
       if msg.role == "system" and msg.opts and msg.opts.context_id == "<group>remove_group</group>" then
         _G.system_msg_exists = true
         break
       end
     end
   ]])

  h.eq(false, child.lua_get("_G.system_msg_exists"), "System message with group context should be removed")
end

return T
