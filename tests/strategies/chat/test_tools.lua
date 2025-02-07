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
  h.eq("foo", messages[#messages].content)
end

T["Tools"][":parse"]["an LLMs response"] = function()
  function add_messages()
    chat:add_buf_message({
      role = "user",
      content = "@foo do some stuff",
    })
    chat:add_buf_message({
      role = "llm",
      content = [[Sure. Let's do this.

```xml
<tools>
  <tool>
    <name>foo</name>
    <content>Some foo function</content>
  </tool>
</tools>
```
]],
    })
  end

  -- Mock out the tools:setup function
  function chat.tools:setup() end

  add_messages()
  chat.header_line = 5

  -- Make sure we parse the whole buffer
  chat.tools:parse_buffer(chat, 5, 100)

  h.eq(
    "<tools>\n  <tool>\n    <name>foo</name>\n    <content>Some foo function</content>\n  </tool>\n</tools>",
    vim.trim(chat.tools.extracted[1])
  )
end

T["Tools"][":replace"] = new_set()

T["Tools"][":replace"]["should replace the tool in the message"] = function()
  local message = "run the @foo tool"
  local result = tools:replace(message, "foo")
  h.eq("run the foo tool", result)
end

return T
