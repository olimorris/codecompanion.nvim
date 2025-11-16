local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _G.tools = h.setup_chat_buffer()
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

T["Tools"] = new_set()

T["Tools"]["resolve"] = new_set()
T["Tools"]["resolve"]["can resolve built-in tools"] = function()
  child.lua([[
    _G.tool = _G.tools.resolve({
      callback = "strategies.chat.tools.catalog.create_file",
      description = "Update a buffer with the LLM's response",
    })
  ]])

  h.eq("table", child.lua_get("type(_G.tool)"))
  h.eq("create_file", child.lua_get("_G.tool.name"))
end

T["Tools"]["resolve"]["can resolve user's tools"] = function()
  child.lua([[
    _G.tool = _G.tools.resolve({
      callback = vim.fn.getcwd() .. "/tests/stubs/foo.lua",
      description = "Some foo function",
    })
  ]])

  h.eq("table", child.lua_get("type(_G.tool)"))
  h.eq("foo", child.lua_get("_G.tool.name"))
  h.eq("This is the Foo tool", child.lua_get("_G.tool.cmds[1]()"))
end

T["Tools"][":find"] = new_set()

T["Tools"][":find"]["should find a group and a tool with same prefix"] = function()
  local result = child.lua([[
    local message = {
      content = "Use @{tool_group_tool} @{tool_group} for something"
    }
    local tools, groups = _G.tools:find(_G.chat, message)
    return {
     tools = tools,
     groups = groups
    }
  ]])

  h.eq({ "tool_group_tool" }, result.tools)
  h.eq({ "tool_group" }, result.groups)
end

T["Tools"][":find"]["should not find a group when tool name starts with group name"] = function()
  local result = child.lua([[
    local message = {
      content = "Use @{tool_group_tool} for something"
    }
    local tools, groups = _G.tools:find(_G.chat, message)
    return {
     tools = tools,
     groups = groups
    }
  ]])

  h.eq({ "tool_group_tool" }, result.tools)
  h.eq({}, result.groups)
end

T["Tools"][":find"]["should find tools added after a chat is initialized"] = function()
  child.lua([[
    --- DO NOT DELETE THIS ---
    --- WE ARE USING THE `codecompanion.config` instead of `tests.config` AS PER #1693 ---
    local config = require("codecompanion.config")

    -- Add a dynamic tool after chat is already created
    config.strategies.chat.tools.dynamic_test_tool = {
    callback = "",
      description = "Dynamic tool",
      enabled = true,
    }

    -- Submit a message with the dynamic tool - this should trigger refresh
    _G.chat:add_buf_message({
      role = "user",
      content = "Use @{dynamic_test_tool} please",
    })
    _G.chat:submit()

    _G.found_dynamic_tool = _G.chat.tool_registry.in_use["dynamic_test_tool"]
    -- Clean up
    config.strategies.chat.tools.dynamic_test_tool = nil
  ]])

  h.eq(true, child.lua_get("_G.found_dynamic_tool"))
end

T["Tools"][":parse"] = new_set()
T["Tools"][":parse"]["add a tool's system prompt to chat buffer"] = function()
  child.lua([[
    local chat = _G.chat
    table.insert(chat.messages, {
      role = "user",
      content = "@{func} do some stuff",
    })

    _G.tools:parse(chat, chat.messages[#chat.messages])
  ]])

  h.eq("default system prompt", child.lua_get([[_G.chat.messages[1].content]]))
  h.eq("my func system prompt", child.lua_get([[_G.chat.messages[3].content]]))
end

T["Tools"][":parse"]["adds a tool's schema"] = function()
  child.lua([[
    local chat = _G.chat
    table.insert(chat.messages, {
      role = "user",
      content = "@{func} do some stuff",
    })
    _G.tools:parse(chat, chat.messages[#chat.messages])
  ]])

  h.eq({ ["<tool>func</tool>"] = { name = "func" } }, child.lua_get([[_G.chat.tool_registry.schemas]]))
end

T["Tools"][":execute"] = new_set()

T["Tools"][":execute"]["a response from the LLM"] = function()
  child.lua([[
    --require("tests.log")
    local tools = {
      {
        id = 1,
        type = "function",
        ["function"] = {
          name = "weather",
          arguments = {
            location = "London, UK",
            units = "celsius",
          },
        },
      },
    }

    local chat = _G.chat
    _G.tools:execute(chat, tools)
  ]])

  local output = child.lua_get([[_G.weather_output]])

  h.eq("The weather in London, UK is 15° celsius", output)
end

T["Tools"][":execute"]["empty response from the LLM"] = function()
  child.lua([[
    --require("tests.log")
    local tools = {
      {
        id = 1,
        type = "function",
        ["function"] = {
          name = "weather_with_default",
          arguments = "",
        },
      },
    }

    local chat = _G.chat
    _G.tools:execute(chat, tools)
  ]])

  local output = child.lua_get([[_G.weather_output]])

  h.eq("The weather in London, UK is 15° celsius", output)
end

T["Tools"][":execute"]["a malformed response from the LLM is handled"] = function()
  child.lua([[
    --require("tests.log")
    local tools = {
      {
        id = 1,
        type = "function",
        ["function"] = {
          name = "weather",
          -- Add an extra } at the end of the arguments
          arguments = '{\"location\": \"London, UK\", \"units\": \"celsius\"}}'
        },
      },
    }

    local chat = _G.chat
    _G.tools:execute(chat, tools)
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])

  h.expect_starts_with("Error calling the `weather` tool: Invalid JSON format", output)
end

T["Tools"][":execute"]["severely malformed JSON from LLM is handled gracefully"] = function()
  child.lua([[
    -- Track events to ensure proper lifecycle
    _G.events_fired = {}

    local aug = vim.api.nvim_create_augroup("test_tool_events", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = aug,
      pattern = "CodeCompanionTools*",
      callback = function(event)
        table.insert(_G.events_fired, event.match)
      end,
    })

    -- Simulate real malformed JSON that crashed the chat
    local tools = {
      {
        id = "call_malformed_123",
        type = "function",
        ["function"] = {
          name = "insert_edit_into_file",
          -- This mimics actual LLM error: incomplete boolean, missing opening brace
          arguments = 'alse{"dryRun": f, "edits": [{"newText":"test","oldText":"old"}], "filepath": "test.lua"}'
        },
      },
    }

    local chat = _G.chat

    -- Simulate the assistant message being added to history first
    -- This is what Chat:done() does before calling tools:execute()
    table.insert(chat.messages, {
      role = require("codecompanion.config").constants.LLM_ROLE,
      content = "",
      tools = {
        calls = tools
      }
    })

    -- Store the count of messages before execution
    _G.message_count_before = #chat.messages

    _G.tools:execute(chat, tools)

    -- Give time for async events
    vim.wait(100)
  ]])

  -- Verify error message was added to chat
  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_starts_with("Error calling the `insert_edit_into_file` tool: Invalid JSON format", output)

  -- Verify helpful guidance is provided
  h.eq(true, output:find("double quotes") ~= nil)
  h.eq(true, output:find("true/false") ~= nil)

  -- Verify ToolsFinished was fired (critical for chat to remain functional)
  local events = child.lua_get("_G.events_fired")
  h.eq(true, vim.tbl_contains(events, "CodeCompanionToolsFinished"))

  -- Verify ToolsStarted was NOT fired (since we failed before orchestrator setup)
  h.eq(false, vim.tbl_contains(events, "CodeCompanionToolsStarted"))

  -- Verify tools status is set to error
  h.eq("error", child.lua_get("_G.tools.status"))

  -- CRITICAL: Verify the malformed assistant message was removed from history
  -- This prevents HTTP 400 on subsequent requests
  child.lua([[
    _G.last_message_in_history = _G.chat.messages[#_G.chat.messages]
    _G.message_count_after = #_G.chat.messages
    _G.has_malformed_assistant_message = false

    -- Check if the malformed assistant message with tool_calls is still in history
    for _, msg in ipairs(_G.chat.messages) do
      if msg.role == require("codecompanion.config").constants.LLM_ROLE
         and msg.tools
         and msg.tools.calls then
        -- Found an assistant message with tool_calls - check if it's the malformed one
        for _, call in ipairs(msg.tools.calls) do
          if call.id == "call_malformed_123" then
            _G.has_malformed_assistant_message = true
            break
          end
        end
      end
    end
  ]])

  -- The malformed assistant message should have been removed
  h.eq(false, child.lua_get("_G.has_malformed_assistant_message"))

  -- Message count should be the same (removed assistant, added tool error)
  h.eq(child.lua_get("_G.message_count_before"), child.lua_get("_G.message_count_after"))

  -- The last message should be the tool error output, not the malformed assistant message
  local last_msg = child.lua_get("_G.last_message_in_history")
  h.eq("tool", last_msg.role)
  h.eq(true, last_msg.content:find("Invalid JSON format") ~= nil)

  -- Verify chat can continue
  child.lua([[
    -- Try to submit another message - this should work
    _G.chat:add_buf_message({
      role = "user",
      content = "Can you try again?",
    })
    _G.can_continue = true
  ]])

  h.eq(true, child.lua_get("_G.can_continue"))
end

T["Tools"][":execute"]["malformed JSON with Python-style booleans"] = function()
  child.lua([[
    -- Test another common malformation: Python True/False
    local tools = {
      {
        id = 1,
        type = "function",
        ["function"] = {
          name = "weather",
          arguments = '{"location": "London", "units": "celsius", "forecast": True}'
        },
      },
    }

    local chat = _G.chat
    _G.tools:execute(chat, tools)
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_starts_with("Error calling the `weather` tool: Invalid JSON format", output)

  -- Should still fire ToolsFinished
  child.lua([[vim.wait(10)]])
  h.eq("error", child.lua_get("_G.tools.status"))
end

T["Tools"][":execute"]["a missing tool is handled"] = function()
  child.lua([[
    local tools = {
      {
        id = 1,
        type = "function",
        ["function"] = {
          name = "missing_tool",
          arguments = {
          },
        },
      },
    }

    local chat = _G.chat
    chat.tool_registry.in_use = {
      weather = true
    }
    _G.tools:execute(chat, tools)
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_starts_with("Tool `missing_tool` not found", output)
  h.eq(true, output:find("`weather`") ~= nil)
end

T["Tools"][":replace"] = new_set()
T["Tools"][":replace"]["should replace the tool in the message"] = function()
  child.lua([[
    local message = "run @{create_file}"
    _G.result = _G.tools:replace(message, "create_file")
  ]])

  h.eq("run the create_file tool", child.lua_get("_G.result"))
end

T["Tools"][":replace"]["should be in sync with finding logic"] = function()
  child.lua([[
    local message = "run @{insert_edit_into_file} and pre@{files} and @{tool_group_tool} and @{files}! and handle newlines @{insert_edit_into_file}\n"
    _G.result = _G.tools:replace(message)
  ]])

  h.eq(
    "run the insert_edit_into_file tool and prethe files tool and the tool_group_tool tool and the files tool! and handle newlines the insert_edit_into_file tool",
    child.lua_get("_G.result")
  )
end

T["Tools"][":replace"]["should replace groups with a prompt message"] = function()
  child.lua([[
    local message = "@{senior_dev}. Can you help?"
    _G.result = _G.tools:replace(message)
  ]])

  h.eq("I'm giving you access to func, cmd tools to help me out. Can you help?", child.lua_get("_G.result"))
end

return T
