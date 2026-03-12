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

T["Editor Context"][":parse_cli"] = new_set()

T["Editor Context"][":parse_cli"]["should return CLI-formatted strings from apply_cli()"] = function()
  child.lua([[
    _G.parse_cli_msg = { content = "#{foo} what does this do?" }
    _G.parse_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.parse_cli_result = _G.ec:parse_cli(_G.parse_cli_ctx, _G.parse_cli_msg)
  ]])

  local results = child.lua_get([[_G.parse_cli_result]])
  h.eq(true, results ~= nil)
  h.eq(1, #results)
  h.eq("cli:foo", results[1])
end

T["Editor Context"][":parse_cli"]["should return nil when no references found"] = function()
  child.lua([[
    _G.parse_cli_msg = { content = "what does this do?" }
    _G.parse_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.parse_cli_result = _G.ec:parse_cli(_G.parse_cli_ctx, _G.parse_cli_msg)
  ]])

  h.eq(true, child.lua_get([[_G.parse_cli_result == nil]]))
end

T["Editor Context"][":parse_cli"]["should handle params correctly"] = function()
  child.lua([[
    _G.parse_cli_msg = { content = "#{bar}{pin} check this" }
    _G.parse_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.parse_cli_result = _G.ec:parse_cli(_G.parse_cli_ctx, _G.parse_cli_msg)
  ]])

  local results = child.lua_get([[_G.parse_cli_result]])
  h.eq(true, results ~= nil)
  h.eq(1, #results)
  h.eq("cli:bar pin", results[1])
end

T["Editor Context"][":parse_cli"]["should skip modules without apply_cli()"] = function()
  child.lua([[
    _G.parse_cli_msg = { content = "#{baz} check this" }
    _G.parse_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.parse_cli_result = _G.ec:parse_cli(_G.parse_cli_ctx, _G.parse_cli_msg)
  ]])

  h.eq(true, child.lua_get([[_G.parse_cli_result == nil]]))
end

T["Editor Context"][":parse_cli"]["should return multiple results for multiple references"] = function()
  child.lua([[
    _G.parse_cli_msg = { content = "#{foo} #{bar} check these" }
    _G.parse_cli_ctx = { bufnr = 1, filetype = "lua" }
    _G.parse_cli_result = _G.ec:parse_cli(_G.parse_cli_ctx, _G.parse_cli_msg)
    table.sort(_G.parse_cli_result)
  ]])

  local results = child.lua_get([[_G.parse_cli_result]])
  h.eq(true, results ~= nil)
  h.eq(2, #results)
  h.eq("cli:bar", results[1])
  h.eq("cli:foo", results[2])
end

return T
