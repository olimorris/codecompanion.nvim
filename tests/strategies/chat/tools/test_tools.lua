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

  h.expect_starts_with("You made an error in calling the weather tool:", output)
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

T["Tools"][":execute"]["a nested response from the LLM"] = function() end

T["Tools"][":replace"] = new_set()
T["Tools"][":replace"]["should replace the tool in the message"] = function()
  child.lua([[
    local message = "run the @{create_file} tool"
    _G.result = _G.tools:replace(message, "create_file")
  ]])

  h.eq("run the create_file tool", child.lua_get("_G.result"))
end

T["Tools"][":replace"]["should be in sync with finding logic"] = function()
  child.lua([[
    local message = "run the @{insert_edit_into_file} tool and pre@{files} and @{tool_group_tool} and @{files}! and handle newlines @{insert_edit_into_file}\n"
    _G.result = _G.tools:replace(message)
  ]])

  h.eq(
    "run the insert_edit_into_file tool and prefiles and tool_group_tool and files! and handle newlines insert_edit_into_file",
    child.lua_get("_G.result")
  )
end

return T
