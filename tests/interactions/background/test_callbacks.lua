local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require('codecompanion.config')
	_G.chat = h.setup_chat_buffer()
	callbacks = require("codecompanion.interactions.background.callbacks")
      ]])
    end,
    post_once = child.stop,
  },
})

T["callbacks"] = new_set()

T["callbacks"]["can register chat callbacks"] = function()
  child.lua([[
    _G.chat = h.setup_chat_buffer()

    -- Mock config with enabled callbacks
    config.interactions.background.chat = {
      opts = { enabled = true },
      callbacks = {
        test_event = {
          enabled = true,
          actions = {}
        }
      }
    }

    -- Track if callback was registered
    local original_add_callback = _G.chat.add_callback
    local callback_registered = false

    _G.chat.add_callback = function(self, event, callback)
      if event == "test_event" then
        callback_registered = true
      end
      return original_add_callback(self, event, callback)
    end

    callbacks.register_chat_callbacks(_G.chat)
    _G.callback_registered = callback_registered
  ]])

  local result = child.lua([[return _G.callback_registered]])

  h.is_true(result)
end

T["callbacks"]["can't register disabled callbacks"] = function()
  child.lua([[
    _G.chat = h.setup_chat_buffer()

    -- Mock config with disabled callbacks
    config.interactions.background.chat = {
      opts = { enabled = true },
      callbacks = {
        test_event = {
          enabled = false,
          actions = {}
        }
      }
    }

    callbacks.register_chat_callbacks(_G.chat)
    _G.callbacks_registered = _G.chat.callbacks.test_event
  ]])

  local result = child.lua([[return _G.callbacks_registered]])

  h.eq(result, vim.NIL)
end

return T
