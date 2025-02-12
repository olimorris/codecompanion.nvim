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

return T
