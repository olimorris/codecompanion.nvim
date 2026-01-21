local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")
        -- fresh chat per case
        _G.chat, _ = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
        _G.chat = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["Subscribers"] = new_set()

T["Subscribers"]["Can subscribe to chat buffer"] = function()
  -- Subscribe an event that appends a message once
  child.lua([[
    local message = "Adding Subscriber Message"
    _G.sub_msg = message
    _G.chat.subscribers:subscribe({
      data = { type = "once" },
      callback = function()
        _G.chat:add_buf_message({ content = message })
      end,
    })
  ]])

  -- queue size is 1
  local size = child.lua([[return _G.chat.subscribers:size()]])
  h.eq(size, 1)

  -- Add a user message so we have content in the buffer
  child.lua([[ _G.chat:add_buf_message({ role = "user", content = "Hello World" }) ]])
  local buffer = child.lua([[ return h.get_buf_lines(_G.chat.bufnr) ]])
  h.eq({ "## foo", "", "Hello World" }, buffer)

  -- Trigger processing; subscriber should add its message and then be removed
  child.lua([[ h.send_to_llm(_G.chat, "Hello there") ]])
  local last_line = child.lua([[
    local lines = h.get_buf_lines(_G.chat.bufnr)
    return lines[#lines]
  ]])
  h.eq(child.lua([[ return _G.sub_msg ]]), last_line)

  size = child.lua([[return _G.chat.subscribers:size()]])
  h.eq(size, 0)

  -- Subsequent runs should not re-add the subscriber message
  child.lua([[ h.send_to_llm(_G.chat, "Hello again") ]])
  buffer = child.lua([[ return h.get_buf_lines(_G.chat.bufnr) ]])
  h.eq("Hello again", buffer[#buffer - 4])
end

T["Subscribers"]["size() reflects queue size"] = function()
  -- Add two once events
  child.lua([[
    _G.ev1 = { data = { type = "once" }, callback = function() end }
    _G.ev2 = { data = { type = "once" }, callback = function() end }
    _G.chat.subscribers:subscribe(_G.ev1)
    _G.chat.subscribers:subscribe(_G.ev2)
  ]])

  local size = child.lua([[return _G.chat.subscribers:size()]])
  h.eq(size, 2)

  -- Unsubscribe first; size should be 1
  child.lua([[ _G.chat.subscribers:unsubscribe(_G.ev1) ]])
  size = child.lua([[return _G.chat.subscribers:size()]])
  h.eq(size, 1)

  -- Processing should consume remaining once event
  child.lua([[ h.send_to_llm(_G.chat, "trigger processing") ]])
  size = child.lua([[return _G.chat.subscribers:size()]])
  h.eq(size, 0)
end

T["Subscribers"]["on_cancelled marks subscribers as stopped"] = function()
  child.lua([[
    local ev = { data = { type = "once", opts = { auto_submit = true } }, callback = function() end }
    _G.chat.subscribers:subscribe(ev)
  ]])

  local size = child.lua([[return _G.chat.subscribers:size()]])
  h.eq(size, 1)

  local stopped = child.lua([[return _G.chat.subscribers.stopped]])
  h.is_false(stopped)

  -- Lifecycle cancel event (wired to subscribers:stop() via on_cancelled)
  child.lua([[ _G.chat:dispatch("on_cancelled") ]])

  stopped = child.lua([[return _G.chat.subscribers.stopped]])
  h.is_true(stopped)
end

return T
