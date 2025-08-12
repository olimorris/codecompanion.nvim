local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, vars

T["Variables"] = new_set({
  hooks = {
    pre_case = function()
      chat, _, vars = h.setup_chat_buffer()
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Variables"][":find"] = new_set()
T["Variables"][":parse"] = new_set()
T["Variables"][":replace"] = new_set()

-- Removed obsolete tests for word boundaries, spaces, newlines, and partial matches

T["Variables"][":parse"]["should parse a message with a variable"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{foo} what does this do?",
  })
  local result = vars:parse(chat, chat.messages[#chat.messages])

  h.eq(true, result)

  local message = chat.messages[#chat.messages]
  h.eq("foo", message.content)
end

T["Variables"][":parse"]["should return nil if no variable is found"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "what does this do?",
  })
  local result = vars:parse(chat, chat.messages[#chat.messages])

  h.eq(false, result)
end

T["Variables"][":parse"]["should parse a message with a variable and string params"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{bar}{pin} Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("bar pin", message.content)
end

T["Variables"][":parse"]["should parse a message with a variable and ignore params if they're not enabled"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{baz}{qux} Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("baz", message.content)
end

T["Variables"][":parse"]["should parse a message with a variable and use default params if set"] = function()
  local config = require("codecompanion.config")
  config.strategies.chat.variables.baz.opts = { default_params = "with default" }

  table.insert(chat.messages, {
    role = "user",
    content = "#{baz} Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("baz with default", message.content)
end

T["Variables"][":parse"]["should parse a message with special characters in variable name"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{screenshot://screenshot-2025-05-21T11-17-45.440Z} what does this do?",
  })
  local result = vars:parse(chat, chat.messages[#chat.messages])

  h.eq(true, result)

  local message = chat.messages[#chat.messages]
  h.eq("Resolved screenshot variable", message.content)
end

T["Variables"][":parse"]["multiple buffer vars"] = function()
  vim.cmd("edit lua/codecompanion/init.lua")
  vim.cmd("edit lua/codecompanion/config.lua")

  table.insert(chat.messages, {
    role = "user",
    content = "Look at #{buffer:init.lua} and then #{buffer:config.lua}",
  })

  local result = vars:parse(chat, chat.messages[#chat.messages])
  h.eq(true, result)

  local buffer_messages = vim.tbl_filter(function(msg)
    return msg.opts and msg.opts.tag == "variable"
  end, chat.messages)

  h.eq(2, #buffer_messages)
end

T["Variables"][":replace"]["should replace the variable in the message"] = function()
  local message = "#{foo} #{bar} replace this var"
  local result = vars:replace(message, 0)
  h.eq("replace this var", result)
end

T["Variables"][":replace"]["should partly replace #buffer in the message"] = function()
  local message = "what does #{buffer} do?"
  local result = vars:replace(message, 0)
  h.expect_starts_with("what does buffer", result)
end

T["Variables"][":replace"]["should replace buffer and the buffer name"] = function()
  vim.cmd("edit lua/codecompanion/init.lua")
  vim.cmd("edit lua/codecompanion/config.lua")

  local message = "what does #{buffer:init.lua} do?"
  local result = vars:replace(message, 0)
  h.expect_starts_with("what does file `lua/codecompanion/init.lua`", result)
end

T["Variables"][":replace"]["should partly replace #buffer in the message"] = function()
  local message = "what does #{buffer}{pin} do?"
  local result = vars:replace(message, 0)
  h.expect_starts_with("what does file ", result)
end

T["Variables"][":replace"]["should be in sync with finding logic"] = function()
  local message =
    "#{foo}{doesnotsupport} #{bar}{supports} #{foo://10-20-30:40} pre#{foo} #{baz}! Use these variables and handle newline var #{foo}\n"
  local result = vars:replace(message, 0)
  h.eq("pre ! Use these variables and handle newline var", result)
end

return T
