local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, vars

T["Variables"] = new_set({
  hooks = {
    pre_once = function()
      chat, _, vars = h.setup_chat_buffer()
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Variables"][":find"] = new_set()
T["Variables"][":parse"] = new_set()
T["Variables"][":replace"] = new_set()

T["Variables"][":find"]["should only find vars that end with space or are eol"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "Use #foo and #foo://10-20-30:40  and not #baz!",
  })

  local found = vars:find(chat.messages[#chat.messages])

  -- Should find all three variables since they are all complete matches
  h.eq(2, #found)
  h.eq(true, vim.tbl_contains(found, "foo"))
  h.eq(true, vim.tbl_contains(found, "foo://10-20-30:40"))
  h.eq(true, not vim.tbl_contains(found, "baz"))
end
T["Variables"][":find"]["should find vars followed by a new line"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "Use #foo\n",
  })

  local found = vars:find(chat.messages[#chat.messages])
  -- Should find all three variables since they are all complete matches
  h.eq(1, #found)
  h.eq(true, vim.tbl_contains(found, "foo"))
end

T["Variables"][":find"]["should find vars with params"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "Use #bar{supports} which supports params and #foo{} that doesn't support params and not #baz{ ",
  })

  local found = vars:find(chat.messages[#chat.messages])
  h.eq(2, #found)
  h.eq(true, vim.tbl_contains(found, "bar") and vim.tbl_contains(found, "foo"))
end

T["Variables"][":find"]["should find vars with non-space chars before"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "Use pre#foo only",
  })

  local found = vars:find(chat.messages[#chat.messages])
  h.eq(1, #found)
  h.eq("foo", found[1])
end

T["Variables"][":find"]["should not find partial variable names"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "Use #foo://10-20-30:40 only",
  })

  local found = vars:find(chat.messages[#chat.messages])

  -- Should only find 'foo://10-20-30:40', not 'foo' as substring
  h.eq(1, #found)
  h.eq("foo://10-20-30:40", found[1])
  h.eq(false, vim.tbl_contains(found, "foo"))
end

T["Variables"][":parse"]["should parse a message with a tool"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#foo what does this do?",
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
    content = "#bar{pin} Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("bar pin", message.content)
end

T["Variables"][":parse"]["should parse a message with a variable and ignore params if they're not enabled"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#baz{qux} Can you parse this variable?",
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
    content = "#baz Can you parse this variable?",
  })
  vars:parse(chat, chat.messages[#chat.messages])

  local message = chat.messages[#chat.messages]
  h.eq("baz with default", message.content)
end

T["Variables"][":parse"]["should parse a message with special characters in variable name"] = function()
  table.insert(chat.messages, {
    role = "user",
    content = "#screenshot://screenshot-2025-05-21T11-17-45.440Z what does this do?",
  })
  local result = vars:parse(chat, chat.messages[#chat.messages])

  h.eq(true, result)

  local message = chat.messages[#chat.messages]
  h.eq("Resolved screenshot variable", message.content)
end

T["Variables"][":replace"]["should replace the variable in the message"] = function()
  local message = "#foo #bar replace this var"
  local result = vars:replace(message, 0)
  h.eq("replace this var", result)
end

T["Variables"][":replace"]["should partly replace #buffer in the message"] = function()
  local message = "what does #buffer do?"
  local result = vars:replace(message, 0)
  h.expect_starts_with("what does buffer 0", result)
end

T["Variables"][":replace"]["should partly replace #buffer in the message"] = function()
  local message = "what does #buffer{pin} do?"
  local result = vars:replace(message, 0)
  h.expect_starts_with("what does buffer 0", result)
end

T["Variables"][":replace"]["should be in sync with finding logic"] = function()
  local message =
    "#foo{doesnotsupport} #bar{supports} #foo://10-20-30:40 pre#foo #baz! Use these variables and handle newline var #foo\n"
  local result = vars:replace(message, 0)
  h.eq("pre #baz! Use these variables and handle newline var", result)
end

return T
