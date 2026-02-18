local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, ec

T["Editor Context"] = new_set({
  hooks = {
    pre_case = function()
      chat, _, ec = h.setup_chat_buffer()
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Editor Context"][":find"] = new_set()
T["Editor Context"][":parse"] = new_set()
T["Editor Context"][":replace"] = new_set()

-- Removed obsolete tests for word boundaries, spaces, newlines, and partial matches

T["Editor Context"][":parse"]["should parse a message with editor context"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{foo} what does this do?",
  })
  local result = ec:parse(chat, chat.messages[#chat.messages])

  h.eq(true, result)

  local message = chat.messages[#chat.messages]
  h.eq("foo", message.content)
end

T["Editor Context"][":parse"]["should return nil if no editor context is found"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "what does this do?",
  })
  local result = ec:parse(chat, chat.messages[#chat.messages])

  h.eq(false, result)
end

T["Editor Context"][":parse"]["should parse a message with editor context and string params"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{bar}{pin} Can you parse this editor context?",
  })
  ec:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("bar pin", message.content)
end

T["Editor Context"][":parse"]["should parse a message with editor context and ignore params if they're not enabled"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{baz}{qux} Can you parse this editor context?",
  })
  ec:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("baz", message.content)
end

T["Editor Context"][":parse"]["should parse a message with editor context and use default params if set"] = function()
  local config = require("codecompanion.config")
  config.interactions.chat.editor_context.baz.opts = { default_params = "with default" }

  table.insert(chat.messages, {
    role = "user",
    content = "#{baz} Can you parse this editor context?",
  })
  ec:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("baz with default", message.content)
end

T["Editor Context"][":parse"]["should parse a message with special characters in the name of editor context"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#{screenshot://screenshot-2025-05-21T11-17-45.440Z} what does this do?",
  })
  local result = ec:parse(chat, chat.messages[#chat.messages])

  h.eq(true, result)

  local message = chat.messages[#chat.messages]
  h.eq("Resolved screenshot editor context", message.content)
end

T["Editor Context"][":parse"]["multiple buffer editor context"] = function()
  vim.cmd("edit lua/codecompanion/init.lua")
  vim.cmd("edit lua/codecompanion/config.lua")

  table.insert(chat.messages, {
    role = "user",
    content = "Look at #{buffer:init.lua} and then #{buffer:config.lua}",
  })

  local result = ec:parse(chat, chat.messages[#chat.messages])
  h.eq(true, result)

  local buffer_messages = vim.tbl_filter(function(msg)
    return msg._meta and msg._meta.tag == "buffer"
  end, chat.messages)

  h.eq(2, #buffer_messages)
end

T["Editor Context"][":parse"]["buffer editor context with params"] = function()
  vim.cmd("edit lua/codecompanion/init.lua")

  table.insert(chat.messages, {
    role = "user",
    content = "Look at #{buffer:init.lua}{all} Isn't it marvellous?",
  })

  ec:parse(chat, chat.messages[#chat.messages])

  local buffer_messages = vim.tbl_filter(function(msg)
    return msg._meta and msg._meta.tag == "buffer"
  end, chat.messages)

  h.eq(1, #buffer_messages)
  h.eq(true, chat.context_items[1].opts.sync_all)
end

T["Editor Context"][":replace"]["should replace the editor context in the message"] = function()
  local message = "#{foo} #{bar} replace this editor context"
  local result = ec:replace(message, 0)
  h.eq("replace this editor context", result)
end

T["Editor Context"][":replace"]["should partly replace #buffer in the message"] = function()
  local message = "what does #{buffer} do?"
  local result = ec:replace(message, 0)
  h.expect_starts_with("what does buffer", result)
end

T["Editor Context"][":replace"]["should replace buffer and the buffer name"] = function()
  vim.cmd("edit lua/codecompanion/init.lua")
  vim.cmd("edit lua/codecompanion/config.lua")

  local message = "what does #{buffer:init.lua} do?"
  local result = ec:replace(message, 0)
  h.expect_match(result, "^what does file `lua[\\/]codecompanion[\\/]init.lua`")
end

T["Editor Context"][":replace"]["should partly replace #buffer in the message"] = function()
  local message = "what does #{buffer}{pin} do?"
  local result = ec:replace(message, 0)
  h.expect_starts_with("what does file ", result)
end

T["Editor Context"][":replace"]["should be in sync with finding logic"] = function()
  local message =
    "#{foo}{doesnotsupport} #{bar}{supports} #{foo://10-20-30:40} pre#{foo} #{baz}! Use these editor context items and handle newline editor context #{foo}\n"
  local result = ec:replace(message, 0)
  h.eq("pre ! Use these editor context items and handle newline editor context", result)
end

return T
