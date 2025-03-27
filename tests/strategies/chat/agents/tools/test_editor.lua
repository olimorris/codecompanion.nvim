local h = require("tests.helpers")

local new_set = MiniTest.new_set

local bufnr

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[vim.g.codecompanion_auto_tool_mode = true]])
      child.lua([[_G.chat, _G.agent = require("tests.helpers").setup_chat_buffer()]])

      -- Setup the buffer
      bufnr = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].readonly = false

    local lines = {
      "function foo()",
      '    return "foo"',
      "end",
      "",
      "function bar()",
      '    return "bar"',
      "end",
      "",
      "function baz()",
      '    return "baz"',
      "end",
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

    return bufnr
  ]])
    end,
    post_case = function()
      _G.xml = nil
    end,
    post_once = child.stop,
  },
})

-- T["Agent @editor can update a buffer"] = function()
--   child.lua(
--     string.format([[    _G.xml = require("tests.strategies.chat.agents.tools.stubs.xml.editor_xml").update(%s)]], bufnr)
--   )
--   child.lua([[
--     _G.agent:execute(
--       _G.chat,
--       _G.xml
--     )
--   ]])
--
--   local lines = child.api.nvim_buf_get_lines(bufnr, 0, -1, false)
--
--   h.eq([[    return "foobar"]], lines[2])
-- end
--
-- T["Agent @editor can add to a buffer"] = function()
--   child.lua(
--     string.format([[    _G.xml = require("tests.strategies.chat.agents.tools.stubs.xml.editor_xml").add(%s)]], bufnr)
--   )
--   child.lua([[
--     _G.agent:execute(
--       _G.chat,
--       _G.xml
--     )
--   ]])
--
--   local lines = child.api.nvim_buf_get_lines(bufnr, 0, -1, false)
--
--   h.eq([[function hello_world()]], lines[4])
--   h.eq([[    return "hello_world"]], lines[5])
--   h.eq([[end]], lines[6])
-- end
--
-- T["Agent @editor can delete from a buffer"] = function()
--   child.lua(
--     string.format([[    _G.xml = require("tests.strategies.chat.agents.tools.stubs.xml.editor_xml").delete(%s)]], bufnr)
--   )
--
--   local lines = child.api.nvim_buf_get_lines(bufnr, 0, -1, false)
--   h.eq([[function foo()]], lines[1])
--   h.eq([[    return "foo"]], lines[2])
--   h.eq([[end]], lines[3])
--
--   child.lua([[
--     _G.agent:execute(
--       _G.chat,
--       _G.xml
--     )
--   ]])
--
--   lines = child.api.nvim_buf_get_lines(bufnr, 0, -1, false)
--
--   h.eq([[function bar()]], lines[1])
--   h.eq([[    return "bar"]], lines[2])
--   h.eq([[end]], lines[3])
-- end

return T
