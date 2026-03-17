local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T["Editor Context"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _, _G.ec = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["Editor Context"][":find"] = new_set()
T["Editor Context"][":parse"] = new_set()
T["Editor Context"][":replace"] = new_set()

-- Removed obsolete tests for word boundaries, spaces, newlines, and partial matches

T["Editor Context"][":parse"]["should parse a message with editor context"] = function()
  child.lua([[
    table.insert(_G.chat.messages, { role = "user", content = "#{foo} what does this do?" })
    _G.result = _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.message = _G.chat.messages[#_G.chat.messages]
  ]])

  h.eq(true, child.lua_get([[_G.result]]))
  h.eq("foo", child.lua_get([[_G.message.content]]))
end

T["Editor Context"][":parse"]["should return nil if no editor context is found"] = function()
  child.lua([[
    table.insert(_G.chat.messages, { role = "user", content = "what does this do?" })
    _G.result = _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
  ]])

  h.eq(false, child.lua_get([[_G.result]]))
end

T["Editor Context"][":parse"]["should parse a message with editor context and string params"] = function()
  child.lua([[
    table.insert(_G.chat.messages, { role = "user", content = "#{bar}{pin} Can you parse this editor context?" })
    _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.message = _G.chat.messages[#_G.chat.messages]
  ]])

  h.eq("bar pin", child.lua_get([[_G.message.content]]))
end

T["Editor Context"][":parse"]["should parse a message with editor context and ignore params if they're not enabled"] = function()
  child.lua([[
    table.insert(_G.chat.messages, { role = "user", content = "#{baz}{qux} Can you parse this editor context?" })
    _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.message = _G.chat.messages[#_G.chat.messages]
  ]])

  h.eq("baz", child.lua_get([[_G.message.content]]))
end

T["Editor Context"][":parse"]["should parse a message with editor context and use default params if set"] = function()
  child.lua([[
    local config = require("codecompanion.config")
    config.interactions.shared.editor_context.baz.opts = { default_params = "with default" }
    table.insert(_G.chat.messages, { role = "user", content = "#{baz} Can you parse this editor context?" })
    _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.message = _G.chat.messages[#_G.chat.messages]
  ]])

  h.eq("baz with default", child.lua_get([[_G.message.content]]))
end

T["Editor Context"][":parse"]["should parse a message with special characters in the name of editor context"] = function()
  child.lua([[
    table.insert(_G.chat.messages, { role = "user", content = "#{screenshot://screenshot-2025-05-21T11-17-45.440Z} what does this do?" })
    _G.result = _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.message = _G.chat.messages[#_G.chat.messages]
  ]])

  h.eq(true, child.lua_get([[_G.result]]))
  h.eq("Resolved screenshot editor context", child.lua_get([[_G.message.content]]))
end

T["Editor Context"][":parse"]["multiple buffer editor context"] = function()
  child.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    vim.cmd("edit lua/codecompanion/config.lua")
    table.insert(_G.chat.messages, { role = "user", content = "Look at #{buffer:init.lua} and then #{buffer:config.lua}" })
    _G.result = _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.buffer_messages = vim.tbl_filter(function(msg)
      return msg._meta and msg._meta.tag == "buffer"
    end, _G.chat.messages)
  ]])

  h.eq(true, child.lua_get([[_G.result]]))
  h.eq(2, child.lua_get([[#_G.buffer_messages]]))
  h.eq(2, child.lua_get([[#_G.chat.context_items]]))
end

T["Editor Context"][":parse"]["buffer editor context with params"] = function()
  child.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    table.insert(_G.chat.messages, { role = "user", content = "Look at #{buffer:init.lua}{all} Isn't it marvellous?" })
    _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.buffer_messages = vim.tbl_filter(function(msg)
      return msg._meta and msg._meta.tag == "buffer"
    end, _G.chat.messages)
  ]])

  h.eq(1, child.lua_get([[#_G.buffer_messages]]))
  h.eq(true, child.lua_get([[_G.chat.context_items[1].opts.sync_all]]))
end

T["Editor Context"][":parse"]["buffers editor context adds context items"] = function()
  child.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    vim.cmd("edit lua/codecompanion/config.lua")
    table.insert(_G.chat.messages, { role = "user", content = "#{buffers} What do these files do?" })
    _G.result = _G.ec:parse(_G.chat, _G.chat.messages[#_G.chat.messages])
    _G.buffer_messages = vim.tbl_filter(function(msg)
      return msg._meta and msg._meta.tag == "buffer"
    end, _G.chat.messages)
    _G.items_valid = true
    for _, item in ipairs(_G.chat.context_items) do
      if item.id == nil or item.bufnr == nil or item.source ~= "codecompanion.interactions.shared.editor_context.buffer" then
        _G.items_valid = false
      end
    end
  ]])

  h.eq(true, child.lua_get([[_G.result]]))
  h.eq(true, child.lua_get([[#_G.buffer_messages >= 2]]))
  h.eq(true, child.lua_get([[#_G.chat.context_items >= 2]]))
  h.eq(true, child.lua_get([[_G.items_valid]]))
end

T["Editor Context"][":replace"]["should replace the editor context in the message"] = function()
  local result = child.lua_get([[_G.ec:replace("#{foo} #{bar} replace this editor context", 0)]])
  h.eq("foo bar replace this editor context", result)
end

T["Editor Context"][":replace"]["should partly replace #buffer in the message"] = function()
  local result = child.lua_get([[_G.ec:replace("what does #{buffer} do?", 0)]])
  h.expect_starts_with("what does file ", result)
end

T["Editor Context"][":replace"]["should replace buffer and the buffer name"] = function()
  child.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    vim.cmd("edit lua/codecompanion/config.lua")
  ]])

  local result = child.lua_get([[_G.ec:replace("what does #{buffer:init.lua} do?", 0)]])
  h.expect_contains("what does file `", result)
  h.expect_contains("lua/codecompanion/init.lua`", result)
end

T["Editor Context"][":replace"]["should partly replace #buffer with params in the message"] = function()
  local result = child.lua_get([[_G.ec:replace("what does #{buffer}{pin} do?", 0)]])
  h.expect_starts_with("what does file ", result)
end

T["Editor Context"][":replace"]["should be in sync with finding logic"] = function()
  local result = child.lua_get(
    [[_G.ec:replace("#{foo}{doesnotsupport} #{bar}{supports} #{foo://10-20-30:40} pre#{foo} #{baz}! Use these editor context items and handle newline editor context #{foo}\n", 0)]]
  )
  h.eq(
    "foo bar foo://10-20-30:40 prefoo baz! Use these editor context items and handle newline editor context foo",
    result
  )
end

T["Editor Context"][":replace_cli"] = new_set()

T["Editor Context"][":replace_cli"]["should use inline labels in the message and append context blocks"] = function()
  child.lua([[
    _G.replace_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.replace_cli_result = _G.ec:replace_cli("what does #{foo} do?", _G.replace_cli_ctx)
  ]])

  local result = child.lua_get([[_G.replace_cli_result]])
  h.expect_starts_with("what does inline:foo do?", result)
  h.expect_contains("cli:foo", result)
end

T["Editor Context"][":replace_cli"]["should handle multiple editor context tags"] = function()
  child.lua([[
    _G.replace_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.replace_cli_result = _G.ec:replace_cli("compare #{foo} and #{bar}", _G.replace_cli_ctx)
  ]])

  local result = child.lua_get([[_G.replace_cli_result]])
  h.expect_contains("inline:foo", result)
  h.expect_contains("inline:bar", result)
  h.expect_contains("cli:foo", result)
  h.expect_contains("cli:bar", result)
end

T["Editor Context"][":replace_cli"]["standalone tag returns only context block"] = function()
  child.lua([[
    _G.replace_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.replace_cli_result = _G.ec:replace_cli("#{foo}", _G.replace_cli_ctx)
  ]])

  local result = child.lua_get([[_G.replace_cli_result]])
  -- Context-only: no inline label, just the context block
  h.eq("cli:foo", result)
end

T["Editor Context"][":replace_cli"]["should skip modules without cli_render"] = function()
  child.lua([[
    _G.replace_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.replace_cli_result = _G.ec:replace_cli("check #{baz} here", _G.replace_cli_ctx)
  ]])

  local result = child.lua_get([[_G.replace_cli_result]])
  -- baz has no cli_render, so tag should be stripped
  h.eq("check  here", result)
end

T["Editor Context"][":replace_cli"]["should handle params"] = function()
  child.lua([[
    _G.replace_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.replace_cli_result = _G.ec:replace_cli("look at #{bar}{pin}", _G.replace_cli_ctx)
  ]])

  local result = child.lua_get([[_G.replace_cli_result]])
  h.expect_contains("inline:bar", result)
  h.expect_contains("cli:bar pin", result)
end

--=============================================================================
-- resolve_editor_context: end-to-end tests using real editor context modules
-- These mirror the keymaps documented in doc/usage/cli.md
--=============================================================================

local child2 = MiniTest.new_child_neovim()
T["resolve_editor_context"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child2)
      child2.lua([[
        h = require("tests.helpers")
        h.setup_plugin()
      ]])
    end,
    post_case = function()
      child2.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child2.stop,
  },
})

T["resolve_editor_context"]["#buffer inline in a sentence"] = function()
  child2.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    local ctx = require("codecompanion.utils.context").get(0)
    local cli = require("codecompanion.interactions.cli")
    _G.result = cli.resolve_editor_context("What does #{buffer} do?", ctx)
  ]])

  local result = child2.lua_get([[_G.result]])
  -- Inline label should be the path with @ prefix, no block appended
  h.expect_contains("What does @", result)
  h.expect_contains("init.lua do?", result)
end

T["resolve_editor_context"]["#buffer standalone returns inline path"] = function()
  child2.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    local ctx = require("codecompanion.utils.context").get(0)
    local cli = require("codecompanion.interactions.cli")
    _G.result = cli.resolve_editor_context("#{buffer}", ctx)
  ]])

  local result = child2.lua_get([[_G.result]])
  h.expect_contains("init.lua", result)
end

T["resolve_editor_context"]["#this with visual selection standalone"] = function()
  child2.lua([[
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta", "gamma" })
    vim.bo[buf].filetype = "lua"
    vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 3, {})

    local ctx = require("codecompanion.utils.context").get(buf, { range = 2 })
    local cli = require("codecompanion.interactions.cli")
    _G.result = cli.resolve_editor_context("#{this}", ctx)
  ]])

  local result = child2.lua_get([[_G.result]])
  -- Context-only: starts directly with the context block
  h.expect_starts_with("- Selected code from", result)
  h.expect_contains("alpha", result)
  h.expect_contains("beta", result)
  -- No redundant inline label before it
  h.eq(nil, result:match("^the selected code"))
end

T["resolve_editor_context"]["#this with visual selection and surrounding text"] = function()
  child2.lua([[
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta", "gamma" })
    vim.bo[buf].filetype = "lua"
    vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 3, {})

    local ctx = require("codecompanion.utils.context").get(buf, { range = 2 })
    local cli = require("codecompanion.interactions.cli")
    _G.result = cli.resolve_editor_context("explain #{this} please", ctx)
  ]])

  local result = child2.lua_get([[_G.result]])
  -- Inline label in sentence
  h.expect_contains("explain the selected code in", result)
  h.expect_contains("please", result)
  -- Context block appended
  h.expect_contains("Selected code from", result)
  h.expect_contains("alpha", result)
end

T["resolve_editor_context"]["#diagnostics with surrounding text"] = function()
  child2.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    local ctx = require("codecompanion.utils.context").get(0)
    local cli = require("codecompanion.interactions.cli")
    _G.result = cli.resolve_editor_context("#{diagnostics} Can you fix these?", ctx)
  ]])

  local result = child2.lua_get([[_G.result]])
  -- When there are no diagnostics, the tag resolves to empty
  -- The important thing is the user text survives
  h.expect_contains("Can you fix these?", result)
end

T["resolve_editor_context"]["multiple tags in a sentence"] = function()
  child2.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")
    vim.cmd("edit lua/codecompanion/config.lua")
    local ctx = require("codecompanion.utils.context").get(0)
    local cli = require("codecompanion.interactions.cli")
    _G.result = cli.resolve_editor_context("compare #{buffer:init.lua} and #{buffer:config.lua}", ctx)
  ]])

  local result = child2.lua_get([[_G.result]])
  h.expect_contains("compare", result)
  h.expect_contains("init.lua", result)
  h.expect_contains("config.lua", result)
end

return T
