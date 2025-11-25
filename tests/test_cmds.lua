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
        config.rules.opts.chat.enabled = false
        h.setup_plugin(config)
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
    -- Ensure clean state
    pcall(CC.close_last_chat)
    _G.calls = { chat = 0, toggle = 0 }
    _G.chat_args = {}
    _G.toggle_err = nil

    local orig_chat, orig_toggle = CC.chat, CC.toggle

    -- Recursion guard
    local call_depth, MAX_DEPTH = 0, 5

    CC.chat = function(args)
      _G.calls.chat = _G.calls.chat + 1
      table.insert(_G.chat_args, args)
      call_depth = call_depth + 1
      if call_depth > MAX_DEPTH then error('Recursion guard tripped in CC.chat') end
      local ok, res = pcall(orig_chat, args)
      call_depth = call_depth - 1
      if not ok then error(res) end
      return res
    end

    CC.toggle = function(window_opts)
      _G.calls.toggle = _G.calls.toggle + 1
      call_depth = call_depth + 1
      if call_depth > MAX_DEPTH then error('Recursion guard tripped in CC.toggle') end
      local ok, res = pcall(orig_toggle, window_opts)
      call_depth = call_depth - 1
      if not ok then error(res) end
      return res
    end

    -- Directly reproduce the old recursion trigger in a controlled way
    local ok, err = pcall(function()
      CC.chat({ fargs = { 'toggle' } })
    end)
    if not ok then
      _G.toggle_err = err
    end

    -- Restore originals
    CC.chat = orig_chat
    CC.toggle = orig_toggle
  ]])

  -- No recursion error should have occurred
  h.eq(vim.NIL, child.lua_get("_G.toggle_err"))

  -- Toggle should be called once by chat(), regardless of how commands are wired
  h.eq(1, child.lua_get("_G.calls.toggle"))

  -- There should be at least one chat() call
  h.expect_truthy(child.lua_get("_G.calls.chat >= 1"))

  -- Any chat() call after the first must NOT forward fargs (sanitized)
  h.eq(
    0,
    child.lua_get([[
    (function()
      local n = 0
      for i = 2, #_G.chat_args do
        if _G.chat_args[i] and _G.chat_args[i].fargs ~= nil then n = n + 1 end
      end
      return n
    end)()
  ]])
  )

  -- A chat instance should exist (don’t assert UI visibility to avoid flakiness)
  h.expect_truthy(child.lua_get("require('codecompanion').last_chat() ~= nil"))
end

T["cmds"]["chat variable syntax highlighting"] = function()
  -- Run entirely inside the child Neovim
  local hl = child.lua([[
    -- Ensure syntax is enabled
    vim.cmd('syntax on')

    -- Make sure test variable exists before setting filetype
    local cfg = require('codecompanion.config')
    cfg.strategies = cfg.strategies or {}
    cfg.strategies.chat = cfg.strategies.chat or {}
    cfg.strategies.chat.variables = cfg.strategies.chat.variables or {}
    cfg.strategies.chat.variables.testvar = cfg.strategies.chat.variables.testvar or {}

    -- New buffer with placeholder
    vim.cmd('enew')
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Some text #{testvar} more text' })

    -- Trigger our FileType autocmd (plugin should already be loaded in pre_once)
    vim.bo[buf].filetype = 'codecompanion'
    vim.cmd('doautocmd FileType codecompanion')
    vim.cmd('doautocmd BufEnter ' .. tostring(buf))

    -- wait for some time so that the `vim.schedule`ed :syntax commands are executed
    vim.wait(10)

    -- Find the column of '#'
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    local col = line:find('#')
    if not col then return 'NO_HASH_FOUND' end

    local id = vim.fn.synID(1, col, 1)
    assert(id ~= 0, string.format('Failed to get the synID for row: %d, col: %d', 1, col))
    return vim.fn.synIDattr(id, 'name')
  ]])

  h.eq(hl, "CodeCompanionChatVariable")
end

return T
