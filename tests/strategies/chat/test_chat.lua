local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, _

T["Chat"] = new_set({
  hooks = {
    pre_once = function()
      chat, _ = h.setup_chat_buffer()
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Chat"]["system prompt is added first"] = function()
  h.eq("system", chat.messages[1].role)
  h.eq("default system prompt", chat.messages[1].content)
end

T["Chat"]["buffer variables are handled"] = function()
  table.insert(chat.messages, { role = "user", content = "#foo what does this file do?" })

  local message = chat.messages[#chat.messages]
  if chat.variables:parse(chat, message) then
    message.content = chat.variables:replace(message.content, chat.context.bufnr)
  end

  -- Variable is inserted as its own new message at the end
  message = chat.messages[#chat.messages]
  h.eq("foo", message.content)
  h.eq(false, message.opts.visible)
  h.eq("variable", message.opts.tag)
end

T["Chat"]["system prompt can be ignored"] = function()
  local new_chat = require("codecompanion.strategies.chat").new({
    ignore_system_prompt = true,
  })

  h.eq(nil, new_chat.messages[1])
end

T["Chat"]["recover method restores a closed chat buffer"] = function()
  local state = {
    messages = { { role = "user", content = "Hello" } },
    settings = { key = "value" },
    refs = {},
    cycle = 1,
    header_line = 1,
    last_role = "user",
  }

  local recovered_chat = require("codecompanion.strategies.chat").recover(state)

  h.eq("Hello", recovered_chat.messages[1].content)
  h.eq("value", recovered_chat.settings.key)
  h.eq(1, recovered_chat.cycle)
  h.eq(1, recovered_chat.header_line)
  h.eq("user", recovered_chat.last_role)
end

T["Chat"]["buffer state is saved before closing"] = function()
  chat:add_buf_message({ role = "user", content = "Hello" })
  chat:close()

  h.eq("Hello", chat.saved_state.messages[1].content)
  h.eq("default system prompt", chat.saved_state.messages[2].content)
end

return T
