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
      content = "Whats the @{weather} like in London? Also adding a @{func} tool too.",
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

  h.eq({
    ["<tool>func</tool>"] = {
      name = "func",
    },
  }, child.lua_get([[chat.tools.schemas]]))
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

  h.expect_starts_with(
    '<attachment filepath="tests/stubs/file.txt">Here is the updated content from the file',
    child.lua_get([[_G.chat.messages[#_G.chat.messages].content]])
  )
  h.eq("<file>tests/stubs/file.txt</file>", child.lua_get([[_G.chat.messages[#_G.chat.messages].opts.reference]]))
end

T["References"]["Correctly removes tool schema and usage flag on reference deletion"] = function()
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
    _G.chat:check_references() -- Sync the refs table initially
  ]])

  -- 2. Verify initial state (both tools present)
  local initial_schemas = child.lua_get([[_G.chat.tools.schemas]])
  local initial_refs_count = child.lua_get([[#_G.chat.refs]])
  local initial_in_use = child.lua_get([[_G.chat.tools.in_use]])

  h.eq(2, vim.tbl_count(initial_schemas), "Should have 2 schemas initially")
  h.expect_truthy(initial_schemas["<tool>weather</tool>"], "Weather schema should exist")
  h.expect_truthy(initial_schemas["<tool>func</tool>"], "Func schema should exist")
  h.eq(2, initial_refs_count, "Should have 2 references initially")
  h.eq({ weather = true, func = true }, initial_in_use, "Both tools should be in use initially")

  -- 3. Simulate deleting the 'weather' tool reference by mocking get_from_chat
  child.lua([[
    -- Mock get_from_chat to simulate user deleting the weather tool reference from the buffer UI
    _G.chat.references.get_from_chat = function()
      -- This function should return a list of reference IDs *currently* found in the buffer
      return { "<tool>func</tool>" } -- Simulate only the func tool reference remaining
    end

    -- Run the check_references function which contains the fix
    _G.chat:check_references()
  ]])

  -- 4. Verify final state (only 'func' tool remains)
  local final_schemas = child.lua_get([[_G.chat.tools.schemas]])
  local final_refs_count = child.lua_get([[#_G.chat.refs]])
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
  h.eq(1, final_refs_count, "Should have 1 reference after deletion")
  h.eq(expected_final_in_use, final_in_use, "Only func tool should be marked in use after deletion")
end

T["References"]["Show icons immediately when added with default parameters"] = function()
  child.lua([[
    -- Test watched reference with default parameters
    _G.chat.references:add({
      id = "<buf>watched_file.lua</buf>",
      path = "test_watched.lua",
      source = "codecompanion.strategies.chat.slash_commands.buffer",
      opts = {
        watched = true,
      },
    })

    -- Test pinned reference with default parameters
    _G.chat.references:add({
      id = "<buf>pinned_file.lua</buf>",
      path = "test_pinned.lua",
      source = "codecompanion.strategies.chat.slash_commands.buffer",
      opts = {
        pinned = true,
      },
    })

    -- Test regular reference for comparison
    _G.chat.references:add({
      id = "<buf>regular_file.lua</buf>",
      path = "test_regular.lua",
      source = "codecompanion.strategies.chat.slash_commands.buffer",
    })
  ]])

  local lines = child.lua_get([[h.get_buf_lines(_G.chat.bufnr)]])

  -- Check that the context header appears
  h.eq("> Context:", lines[3])

  -- Check that watched reference shows with icon immediately
  h.eq(
    string.format("> - %s<buf>watched_file.lua</buf>", child.lua_get([[config.display.chat.icons.buffer_watch]])),
    lines[4]
  )

  -- Check that pinned reference shows with icon immediately
  h.eq(
    string.format("> - %s<buf>pinned_file.lua</buf>", child.lua_get([[config.display.chat.icons.buffer_pin]])),
    lines[5]
  )

  -- Check that regular reference shows without icon
  h.eq("> - <buf>regular_file.lua</buf>", lines[6])
end

T["References"]["Tool group with collapse_tools shows single group reference"] = function()
  child.lua([[
    local message = { role = "user", content = "@{test_group} help" }
    _G.chat:add_message(message)
    _G.chat:replace_vars_and_tools(message)
  ]])

  local refs_in_chat = child.lua_get([[_G.chat.references:get_from_chat()]])
  h.expect_tbl_contains("<group>test_group</group>", refs_in_chat)

  -- Verify system message was added with group reference
  child.lua([[
    _G.system_msg = nil
    for _, msg in ipairs(_G.chat.messages) do
      if msg.role == "system" and msg.opts and msg.opts.reference == "<group>test_group</group>" then
        _G.system_msg = { content = msg.content, reference = msg.opts.reference }
        break
      end
    end
  ]])

  local system_msg = child.lua_get("_G.system_msg")
  h.eq("Test group system prompt", system_msg.content)
  h.eq("<group>test_group</group>", system_msg.reference)
end

T["References"]["Tool group without collapse_tools shows individual tools"] = function()
  child.lua([[
    local message = { role = "user", content = "@{test_group2} help" }
    _G.chat:add_message(message)
    _G.chat:replace_vars_and_tools(message)
  ]])

  local refs_in_chat = child.lua_get([[_G.chat.references:get_from_chat()]])
  h.expect_tbl_contains("<tool>func</tool>", refs_in_chat)
  h.expect_tbl_contains("<tool>weather</tool>", refs_in_chat)

  -- Verify system message still has group reference even with individual tools
  child.lua([[
    _G.system_msg_content = nil
    for _, msg in ipairs(_G.chat.messages) do
      if msg.role == "system" and msg.opts and msg.opts.reference == "<group>test_group2</group>" then
        _G.system_msg_content = msg.content
        break
      end
    end
  ]])

  local system_msg = child.lua_get("_G.system_msg_content")
  h.eq("Individual tools system prompt", system_msg)
end

T["References"]["Removing collapsed group removes all its tools and system message"] = function()
  child.lua([[
    local message = { role = "user", content = "@{remove_group} help" }
    _G.chat:add_message(message)
    _G.chat:replace_vars_and_tools(message)
  ]])

  -- Verify initial state
  child.lua([[
    _G.initial_system_msg_found = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg.role == "system" and msg.opts and msg.opts.reference == "<group>remove_group</group>" then
        _G.initial_system_msg_found = true
        break
      end
    end
  ]])

  h.eq(true, child.lua_get("_G.initial_system_msg_found"), "System message should exist initially")

  child.lua([[
    -- Mock removing the group reference
    _G.chat.references.get_from_chat = function() return {} end
    _G.chat:check_references()
  ]])

  local final_schemas = child.lua_get([[_G.chat.tools.schemas]])
  local final_in_use = child.lua_get([[_G.chat.tools.in_use]])

  h.eq({}, final_schemas, "All tool schemas should be removed")
  h.eq({}, final_in_use, "All tools should be removed from in_use")

  -- Verify system message with group reference is removed
  child.lua([[
    _G.system_msg_exists = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg.role == "system" and msg.opts and msg.opts.reference == "<group>remove_group</group>" then
        _G.system_msg_exists = true
        break
      end
    end
  ]])

  h.eq(false, child.lua_get("_G.system_msg_exists"), "System message with group reference should be removed")
end

return T
