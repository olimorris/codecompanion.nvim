local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, tools

T["Tools"] = new_set({
  hooks = {
    pre_case = function()
      chat, tools = h.setup_chat_buffer()
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Tools"][":parse"] = new_set()

T["Tools"][":parse"]["a message with a tool"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "@foo do some stuff",
  })
  tools:parse(chat, chat.messages[#chat.messages])
  local messages = chat.messages

  h.eq("My tool system prompt", messages[#messages - 1].content)
  h.eq("my foo system prompt", messages[#messages].content)
end

T["Tools"][":parse"]["a response from the LLM"] = function()
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
  chat.tools.chat = chat
  chat.tools:parse_buffer(chat, 5, 100)

  local lines = h.get_buf_lines(chat.bufnr)
  h.eq("This is from the foo tool", lines[#lines])
end

T["Tools"][":parse"]["a nested response from the LLM"] = function()
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
  chat.tools.chat = chat
  chat.tools:parse_buffer(chat, 5, 100)

  local lines = h.get_buf_lines(chat.bufnr)
  h.eq("This is from the foo toolThis is from the bar tool", lines[#lines])
end

T["Tools"][":replace"] = new_set()

T["Tools"][":replace"]["should replace the tool in the message"] = function()
  local message = "run the @foo tool"
  local result = tools:replace(message, "foo")
  h.eq("run the foo tool", result)
end

return T
