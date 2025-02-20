local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, tools

T["Tools"] = new_set({
  hooks = {
    pre_case = function()
      chat, tools = h.setup_chat_buffer()
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

-- T["Tools"]["resolve"] = new_set()
--
-- T["Tools"]["resolve"]["can resolve built-in tools"] = function()
--   local tool = tools.resolve({
--     callback = "strategies.chat.tools.editor",
--     description = "Update a buffer with the LLM's response",
--   })
--
--   h.eq(type(tool), "table")
--   h.eq("editor", tool.name)
--   h.eq(6, #tool.schema)
-- end
--
-- T["Tools"]["resolve"]["can resolve user's tools"] = function()
--   local tool = tools.resolve({
--     callback = vim.fn.getcwd() .. "/tests/stubs/foo.lua",
--     description = "Some foo function",
--   })
--
--   h.eq(type(tool), "table")
--   h.eq("foo", tool.name)
--   h.eq("This is the Foo tool", tool.cmds[1]())
-- end
--
-- T["Tools"][":parse"] = new_set()
--
-- T["Tools"][":parse"]["a message with a tool"] = function()
--   table.insert(chat.messages, {
--     role = "user",
--     content = "@foo do some stuff",
--   })
--   tools:parse(chat, chat.messages[#chat.messages])
--   local messages = chat.messages
--
--   h.eq("My tool system prompt", messages[#messages - 1].content)
--   h.eq("my foo system prompt", messages[#messages].content)
-- end
--
-- T["Tools"][":parse"]["a response from the LLM"] = function()
--   chat:add_buf_message({
--     role = "user",
--     content = "@foo do some stuff",
--   })
--   chat:add_buf_message({
--     role = "llm",
--     content = [[Sure. Let's do this.
--
-- ```xml
-- <tools>
--   <tool name="foo">
--     <content>Some foo function</content>
--   </tool>
-- </tools>
-- ```
-- ]],
--   })
--   chat.tools.chat = chat
--   chat.tools:parse_buffer(chat, 5, 100)
--
--   local lines = h.get_buf_lines(chat.bufnr)
--   h.eq("This is from the foo tool", lines[#lines])
-- end
--
-- T["Tools"][":parse"]["a nested response from the LLM"] = function()
--   chat:add_buf_message({
--     role = "user",
--     content = "@foo @bar do some stuff",
--   })
--   chat:add_buf_message({
--     role = "llm",
--     content = [[Sure. Let's do this.
--
-- ```xml
-- <tools>
--   <tool name="foo">
--     <content>Some foo function</content>
--   </tool>
--   <tool name="bar">
--     <content>Some bar function</content>
--   </tool>
-- </tools>
-- ```
-- ]],
--   })
--   chat.tools.chat = chat
--   chat.tools:parse_buffer(chat, 5, 100)
--
--   local lines = h.get_buf_lines(chat.bufnr)
--   h.eq("This is from the foo toolThis is from the bar tool", lines[#lines])
-- end
--
-- T["Tools"][":replace"] = new_set()
--
-- T["Tools"][":replace"]["should replace the tool in the message"] = function()
--   local message = "run the @foo tool"
--   local result = tools:replace(message, "foo")
--   h.eq("run the foo tool", result)
-- end

T["Tools"][":setup"] = new_set()

T["Tools"][":setup"]["can run functions"] = function()
  h.eq(vim.g.codecompanion_test, nil)
  tools:setup(
    chat,
    [[<tools>
  <tool name="func">
    <action type="type1"><data>Data 1</data></action>
    <action type="type2"><data>Data 2</data></action>
  </tool>
</tools>]]
  )
  h.eq("Data 1 Data 2", vim.g.codecompanion_test)
  vim.g.codecompanion_test = nil
end

T["Tools"][":setup"]["can run consecutive functions"] = function()
  h.eq(vim.g.codecompanion_test, nil)
  tools:setup(
    chat,
    [[<tools>
  <tool name="func_consecutive">
    <action type="type1"><data>Data 1</data></action>
  </tool>
</tools>]]
  )
  h.eq("Data 1 Data 1", vim.g.codecompanion_test)
  vim.g.codecompanion_test = nil
end

T["Tools"][":setup"]["can run multiple, consecutive functions"] = function()
  h.eq(vim.g.codecompanion_test, nil)
  tools:setup(
    chat,
    [[<tools>
  <tool name="func_consecutive">
    <action type="type1"><data>Data 1</data></action>
    <action type="type2"><data>Data 2</data></action>
  </tool>
</tools>]]
  )
  h.eq("Data 2 Data 2", vim.g.codecompanion_test)
  vim.g.codecompanion_test = nil
end

return T
