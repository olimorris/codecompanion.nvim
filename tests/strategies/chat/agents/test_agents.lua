local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _G.agent = h.setup_chat_buffer()
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

T["Agent"] = new_set()

T["Agent"]["resolve"] = new_set()
T["Agent"]["resolve"]["can resolve built-in tools"] = function()
  child.lua([[
    _G.tool = _G.agent.resolve({
      callback = "strategies.chat.agents.tools.editor",
      description = "Update a buffer with the LLM's response",
    })
  ]])

  h.eq("table", child.lua_get("type(_G.tool)"))
  h.eq("editor", child.lua_get("_G.tool.name"))
end

T["Agent"]["resolve"]["can resolve user's tools"] = function()
  child.lua([[
    _G.tool = _G.agent.resolve({
      callback = vim.fn.getcwd() .. "/tests/stubs/foo.lua",
      description = "Some foo function",
    })
  ]])

  h.eq("table", child.lua_get("type(_G.tool)"))
  h.eq("foo", child.lua_get("_G.tool.name"))
  h.eq("This is the Foo tool", child.lua_get("_G.tool.cmds[1]()"))
end

T["Agent"][":parse"] = new_set()
T["Agent"][":parse"]["add a tool's system prompt to chat buffer"] = function()
  child.lua([[
    local chat = _G.chat
    table.insert(chat.messages, {
      role = "user",
      content = "@func do some stuff",
    })

    _G.agent:parse(chat, chat.messages[#chat.messages])
  ]])

  h.eq("default system prompt", child.lua_get([[_G.chat.messages[1].content]]))
  h.eq("my func system prompt", child.lua_get([[_G.chat.messages[3].content]]))
end

T["Agent"][":parse"]["adds a tool's schema"] = function()
  child.lua([[
    local chat = _G.chat
    table.insert(chat.messages, {
      role = "user",
      content = "@func do some stuff",
    })
    _G.agent:parse(chat, chat.messages[#chat.messages])
  ]])

  h.eq({ ["<tool>func</tool>"] = { name = "func" } }, child.lua_get([[_G.chat.tools.schemas]]))
end

T["Agent"][":execute"] = new_set()
T["Agent"][":execute"]["a response from the LLM"] = function()
  child.lua([[
    require("tests.log")
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
    _G.agent:execute(chat, tools)
  ]])

  local output = child.lua_get([[_G.weather_output]])

  h.eq("The weather in London, UK is 75° celsius", output)
end

T["Agent"][":execute"]["a nested response from the LLM"] = function() end

T["Agent"][":replace"] = new_set()
T["Agent"][":replace"]["should replace the tool in the message"] = function()
  child.lua([[
    local message = "run the @editor tool"
    _G.result = _G.agent:replace(message, "editor")
  ]])

  h.eq("run the editor tool", child.lua_get("_G.result"))
end

return T
