local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require('codecompanion.config')
        config.memory.opts.chat.enabled = false
        h.setup_plugin()
      ]])
    end,
    post_once = child.stop,
  },
})

T["cmds"] = new_set()
T["cmds"][":CodeCompanionChat"] = function()
  child.lua([[
    -- Mock the submit function
    local original = h.mock_submit("This is a mocked response: 1 + 1 = 2")

    -- Run the command
    vim.cmd("CodeCompanionChat this is a test, what is 1 + 1?")
    vim.wait(100)

    -- Restore the original function
    h.restore_submit(original)
  ]])
  expect.reference_screenshot(child.get_screenshot())
end

T["cmds"][":CodeCompanionChat Toggle"] = function()
  child.cmd([[tabnew]])
  child.cmd([[CodeCompanionChat Toggle]])
  expect.reference_screenshot(child.get_screenshot())
end

T["cmds"]["sticky chat window"] = function()
  child.lua([[
    require('codecompanion').setup({
      display = {
        chat = {
          window = {
            layout = "vertical",
            sticky = true
          }
        }
      }
    })
    vim.cmd("CodeCompanionChat")
    vim.cmd("tabnew")
  ]])

  -- expect.reference_screenshot(child.get_screenshot())
  -- window opened
  h.eq(true, child.lua_get("require('codecompanion').last_chat().ui:is_visible()"))
  -- window opened in the current tab (in other words, NOT in NON_CURRENT tab)
  h.eq(false, child.lua_get("require('codecompanion').last_chat().ui:is_visible_non_curtab()"))
end

T["cmds"][":CodeCompanionChat Toggle does not recurse when no chat exists"] = function()
  child.lua([[
    local CC = require('codecompanion')
    _G.calls = { chat = 0, toggle = 0 }
    _G.chat_args = {}
    _G.toggle_err = nil

    local orig_chat, orig_toggle = CC.chat, CC.toggle

    -- Recursion guard
    local call_depth = 0
    local MAX_DEPTH = 5

    CC.chat = function(args)
      _G.calls.chat = _G.calls.chat + 1
      table.insert(_G.chat_args, args)
      call_depth = call_depth + 1
      if call_depth > MAX_DEPTH then
        error('Recursion guard tripped in CC.chat')
      end
      local ok, res = pcall(orig_chat, args)
      call_depth = call_depth - 1
      if not ok then error(res) end
      return res
    end

    CC.toggle = function(window_opts)
      _G.calls.toggle = _G.calls.toggle + 1
      call_depth = call_depth + 1
      if call_depth > MAX_DEPTH then
        error('Recursion guard tripped in CC.toggle')
      end
      local ok, res = pcall(orig_toggle, window_opts)
      call_depth = call_depth - 1
      if not ok then error(res) end
      return res
    end

    -- Run the command that previously caused recursion, but protected
    local ok, err = pcall(vim.cmd, 'CodeCompanionChat Toggle')
    if not ok then
      _G.toggle_err = err
    end

    -- Restore originals
    CC.chat = orig_chat
    CC.toggle = orig_toggle
  ]])

  -- No recursion error should have occurred
  h.eq(vim.NIL, child.lua_get("_G.toggle_err"))

  -- chat is called first by the command (with fargs), then by toggle (without fargs)
  h.eq(2, child.lua_get("_G.calls.chat"))
  h.eq(1, child.lua_get("_G.calls.toggle"))

  -- First chat call had fargs; second (from toggle) was sanitized (no fargs)
  h.expect_truthy(child.lua_get("_G.chat_args[1] and _G.chat_args[1].fargs ~= nil"))
  h.eq(vim.NIL, child.lua_get("_G.chat_args[2] and _G.chat_args[2].fargs"))

  -- And the window should be visible (no freeze)
  h.eq(true, child.lua_get("require('codecompanion').last_chat().ui:is_visible()"))
end

T["cmds"][":CodeCompanionChat Toggle can be opened with layout options"] = function()
  child.lua([[
    require("codecompanion").toggle({ window_opts = { layout = "float" } })
  ]])
  expect.reference_screenshot(child.get_screenshot())
end

return T
