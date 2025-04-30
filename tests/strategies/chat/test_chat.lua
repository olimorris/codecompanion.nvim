local h = require("tests.helpers")

local expect = MiniTest.expect
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
        _G.chat, _G.agent = h.setup_chat_buffer()
        ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Chat"] = new_set()

T["Chat"]["system prompt is added first"] = function()
  local messages = child.lua_get([[_G.chat.messages]])
  h.eq("system", messages[1].role)
  h.eq("default system prompt", messages[1].content)
end

T["Chat"]["buffer variables are handled"] = function()
  -- Execute all the complex operations in the child process
  child.lua([[
    -- Get the existing chat object
    local chat = _G.chat

    -- Add a new message with a variable reference
    table.insert(chat.messages, { role = "user", content = "#foo what does this file do?" })

    -- Get the message we just added
    local message = chat.messages[#chat.messages]

    -- Parse and replace variables in the message
    if chat.variables:parse(chat, message) then
      message.content = chat.variables:replace(message.content, chat.context.bufnr)
    end

    -- Extract the properties we need to test into simple data types
    _G.last_message_content = chat.messages[#chat.messages].content
    _G.last_message_visible = chat.messages[#chat.messages].opts.visible
    _G.last_message_tag = chat.messages[#chat.messages].opts.tag
  ]])

  -- Retrieve the simple values from the child process
  local last_message_content = child.lua_get([[_G.last_message_content]])
  local last_message_visible = child.lua_get([[_G.last_message_visible]])
  local last_message_tag = child.lua_get([[_G.last_message_tag]])

  -- Make assertions on the retrieved values
  h.eq("foo", last_message_content)
  h.eq(false, last_message_visible)
  h.eq("variable", last_message_tag)
end

T["Chat"]["system prompt can be ignored"] = function()
  child.lua([[_G.new_chat = require("codecompanion.strategies.chat").new({
    ignore_system_prompt = true,
  })]])

  local new_chat = child.lua_get([[_G.new_chat.messages]])

  h.eq(nil, new_chat[1])
end

T["Chat"]["chat buffer is initialized"] = function()
  child.lua([[require("codecompanion").chat()]])
  expect.reference_screenshot(child.get_screenshot())
end

T["Chat"]["loading from the prompt library sets the correct header_line"] = function()
  local output = child.lua([[
    require("tests.log")
    -- Load the demo prompt from the prompt library
    codecompanion.prompt("demo")
    -- Get the chat object
    local bufnr = vim.api.nvim_get_current_buf()
    local chat = codecompanion.buf_get_chat(bufnr)
    return chat.header_line
  ]])

  expect.reference_screenshot(child.get_screenshot())
  h.eq(9, output)
end

return T
