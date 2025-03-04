local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, agent

T["Agent"] = new_set({
  hooks = {
    pre_case = function()
      chat, agent = h.setup_chat_buffer()
    end,
    post_case = function()
      h.teardown_chat_buffer()
      vim.g.codecompanion_test = nil
      vim.g.codecompanion_test_exit = nil
      vim.g.codecompanion_test_output = nil
    end,
  },
})

T["Agent"]["resolve"] = new_set()

T["Agent"]["resolve"]["can resolve built-in tools"] = function()
  local tool = agent.resolve({
    callback = "strategies.chat.agents.tools.editor",
    description = "Update a buffer with the LLM's response",
  })

  h.eq(type(tool), "table")
  h.eq("editor", tool.name)
  h.eq(6, #tool.schema)
end

T["Agent"]["resolve"]["can resolve user's tools"] = function()
  local tool = agent.resolve({
    callback = vim.fn.getcwd() .. "/tests/stubs/foo.lua",
    description = "Some foo function",
  })

  h.eq(type(tool), "table")
  h.eq("foo", tool.name)
  h.eq("This is the Foo tool", tool.cmds[1]())
end

T["Agent"][":parse"] = new_set()

T["Agent"][":parse"]["a message with a tool"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "@foo do some stuff",
  })
  agent:parse(chat, chat.messages[#chat.messages])
  local messages = chat.messages

  h.eq("My tool system prompt", messages[#messages - 1].content)
  h.eq("my foo system prompt", messages[#messages].content)
end

T["Agent"][":parse"]["a response from the LLM"] = function()
  chat:add_buf_message({
    role = "user",
    content = "@foo do some stuff",
  })
  chat:add_buf_message({
    role = "llm",
    content = [[Sure. Let's do this.

```xml
<tools>
  <tool name="foo">
    <content>Some foo function</content>
  </tool>
</tools>
```
]],
  })
  chat.agents.chat = chat
  chat.agents:parse_buffer(chat, 5, 100)

  local lines = h.get_buf_lines(chat.bufnr)
  h.eq("This is from the foo tool", lines[#lines])
end

T["Agent"][":parse"]["a nested response from the LLM"] = function()
  chat:add_buf_message({
    role = "user",
    content = "@foo @bar do some stuff",
  })
  chat:add_buf_message({
    role = "llm",
    content = [[Sure. Let's do this.

```xml
<tools>
  <tool name="foo">
    <content>Some foo function</content>
  </tool>
  <tool name="bar">
    <content>Some bar function</content>
  </tool>
</tools>
```
]],
  })
  chat.agents.chat = chat
  chat.agents:parse_buffer(chat, 5, 100)

  local lines = h.get_buf_lines(chat.bufnr)
  h.eq("This is from the foo toolThis is from the bar tool", lines[#lines])
end

T["Agent"][":replace"] = new_set()

T["Agent"][":replace"]["should replace the tool in the message"] = function()
  local message = "run the @foo tool"
  local result = agent:replace(message, "foo")
  h.eq("run the foo tool", result)
end

return T
