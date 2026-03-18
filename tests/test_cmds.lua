local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

T = new_set()

T["cmds"] = new_set({
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
    _G.calls = { chat = 0, toggle_chat = 0 }
    _G.chat_args = {}
    _G.toggle_err = nil

    local orig_chat, orig_toggle_chat = CC.chat, CC.toggle_chat

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

    CC.toggle_chat = function(args)
      _G.calls.toggle_chat = _G.calls.toggle_chat + 1
      call_depth = call_depth + 1
      if call_depth > MAX_DEPTH then error('Recursion guard tripped in CC.toggle_chat') end
      local ok, res = pcall(orig_toggle_chat, args)
      call_depth = call_depth - 1
      if not ok then error(res) end
      return res
    end

    -- Test with the new subcommand format
    local ok, err = pcall(function()
      CC.chat({ subcommand = 'toggle' })
    end)
    if not ok then
      _G.toggle_err = err
    end

    -- Restore originals
    CC.chat = orig_chat
    CC.toggle_chat = orig_toggle_chat
  ]])

  -- No recursion error should have occurred
  h.eq(vim.NIL, child.lua_get("_G.toggle_err"))

  -- toggle_chat should be called once by chat()
  h.eq(1, child.lua_get("_G.calls.toggle_chat"))

  -- Chat should be called at least once (by the test), and possibly again by toggle_chat
  h.expect_truthy(child.lua_get("_G.calls.chat >= 1"))

  -- The first chat() call should have subcommand set
  h.eq(
    "toggle",
    child.lua_get([[
      _G.chat_args[1] and _G.chat_args[1].subcommand or vim.NIL
    ]])
  )

  -- A chat instance should exist (don't assert UI visibility to avoid flakiness)
  h.expect_truthy(child.lua_get("require('codecompanion').last_chat() ~= nil"))
end

T["cmds"]["chat variable syntax highlighting"] = function()
  -- Run entirely inside the child Neovim
  local hl = child.lua([[
    -- Ensure syntax is enabled
    vim.cmd('syntax on')

    -- Make sure test variable exists before setting filetype
    local cfg = require('codecompanion.config')
    cfg.interactions = cfg.interactions or {}
    cfg.interactions.shared = cfg.interactions.shared or {}
    cfg.interactions.shared.editor_context = cfg.interactions.shared.editor_context or {}
    cfg.interactions.shared.editor_context.testvar = cfg.interactions.shared.editor_context.testvar or {}

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

  h.eq(hl, "CodeCompanionChatEditorContext")
end

T["cmds_cli"] = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        local config = require("codecompanion.config")
        config.interactions.cli.agents = {
          test_agent_a = { cmd = "cat", args = {}, description = "Agent A" },
          test_agent_b = { cmd = "cat", args = {}, description = "Agent B" },
        }
        config.interactions.cli.agent = "test_agent_a"
        h.setup_plugin(config)
      ]])
    end,
    pre_case = function()
      child.lua([[
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(bufnr)
          if name:find("%[CodeCompanion CLI%]") then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
          end
        end
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if win ~= vim.api.nvim_list_wins()[1] then
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
        package.loaded["codecompanion.interactions.cli"] = nil
        package.loaded["codecompanion"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["cmds_cli"][":CodeCompanionCLI with no args creates a new instance"] = function()
  child.lua([[vim.cmd("CodeCompanionCLI")]])

  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local instance = cli.last_cli()
    return {
      created = instance ~= nil,
      visible = instance and instance.ui:is_visible(),
    }
  ]])

  h.eq(true, result.created)
  h.eq(true, result.visible)
end

T["cmds_cli"][":CodeCompanionCLI with prompt reuses last instance"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")

    vim.cmd("CodeCompanionCLI")
    local first_bufnr = cli.last_cli().bufnr

    vim.cmd("CodeCompanionCLI hello")
    local second_bufnr = cli.last_cli().bufnr

    return {
      same_instance = first_bufnr == second_bufnr,
    }
  ]])

  h.eq(true, result.same_instance)
end

T["cmds_cli"][":CodeCompanionCLI with agent= creates instance with that agent"] = function()
  local result = child.lua([[
    vim.cmd("CodeCompanionCLI agent=test_agent_b")

    local cli = require("codecompanion.interactions.cli")
    local instance = cli.last_cli()
    return {
      agent = instance and instance.agent_name,
    }
  ]])

  h.eq("test_agent_b", result.agent)
end

T["cmds_tab"] = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require('codecompanion.config')
        config.rules.opts.chat.enabled = false
        config.display.chat.window.layout = "tab"
        config.display.chat.intro_message = "Welcome"
        h.setup_plugin(config)
      ]])
    end,
    post_once = child.stop,
  },
})

T["cmds_tab"][":CodeCompanionChat opens in tab when set in config"] = function()
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

T["cmds_tab"][":CodeCompanionChat Toggle goes to last tab from chat"] = function()
  child.cmd([[CodeCompanionChat Toggle]])
  expect.reference_screenshot(child.get_screenshot())
end

T["cmds_tab"][":CodeCompanionChat Toggle goes to chat from any other tab"] = function()
  child.cmd([[CodeCompanionChat Toggle]])
  expect.reference_screenshot(child.get_screenshot())
end

T["cmds_tab"][":CodeCompanionChat Toggle after reopen does not error"] = function()
  -- Reproduce: open chat, close it, reopen, then Toggle twice
  -- Previously caused E475 because tabnext received a tabpage handle
  -- instead of a tab index
  child.lua([[vim.cmd("CodeCompanionChat")]])
  child.cmd([[q]])
  child.lua([[vim.cmd("CodeCompanionChat")]])
  local ok, err = child.lua([[return pcall(function()
    vim.cmd("CodeCompanionChat Toggle")
    vim.cmd("CodeCompanionChat Toggle")
  end)]])
  h.eq(true, ok)
end

T["cmds_tab_sticky"] = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require('codecompanion.config')
        config.rules.opts.chat.enabled = false
        config.display.chat.window.layout = "tab"
        config.display.chat.window.sticky = true
        config.display.chat.intro_message = "Welcome"
        h.setup_plugin(config)
      ]])
    end,
    post_once = child.stop,
  },
})

T["cmds_tab_sticky"][":CodeCompanionChat doesnt follow if sticky is set"] = function()
  child.lua([[
    -- Mock the submit function
    local original = h.mock_submit("This is a mocked response: 1 + 1 = 2")

    -- Run the command
    vim.cmd("CodeCompanionChat this is a test, what is 1 + 1?")
    vim.wait(100)

    -- Restore the original function
    h.restore_submit(original)

    -- Open a new tab
    vim.cmd("tabnew")
  ]])
  expect.reference_screenshot(child.get_screenshot())
end

return T
