local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

T["Memory.make() with string rule"] = function()
  local tmp = child.lua("return vim.fn.tempname()")
  local content = "This is a test memory content"
  child.fn.writefile({ content }, tmp)

  -- Monkey-patch helpers to capture the processed data and chat
  child.lua(string.format([[
    package.loaded['codecompanion.strategies.chat.memory.helpers'] = {
      add_context = function(processed, chat)
        _G.__memory_processed = processed
        _G.__memory_chat = chat
      end
    }
  ]]))

  -- Require the memory module and run make()
  child.lua(string.format(
    [[
    local mem = require("codecompanion.strategies.chat.memory.init")
    mem.init({ name = "test", rules = { %q } }):make({ id = "chat-1" })
  ]],
    tmp
  ))

  -- Get captured values and expected filename
  local processed = child.lua("return _G.__memory_processed")
  local captured_chat = child.lua("return _G.__memory_chat")
  local expected_filename = child.lua("return vim.fn.fnamemodify(..., ':t')", { tmp })
  local expected_filepath = child.lua("return vim.fs.normalize(...)", { tmp })

  -- Assertions
  h.eq(type(processed), "table")
  h.eq(#processed, 1)
  h.eq(processed[1].content, content .. "\n") -- Always adds a blank line
  h.eq(processed[1].filename, expected_filename)
  h.eq(processed[1].filepath, expected_filepath)
  h.eq(captured_chat.id, "chat-1")
end

T["Memory.make() with table rule (path + parser)"] = function()
  -- Create a temporary file for the second case
  local tmp2 = child.lua("return vim.fn.tempname()")
  local content2 = "Parser test content"
  child.fn.writefile({ content2 }, tmp2)

  -- Patch helpers again (fresh globals)
  child.lua(string.format([[
    package.loaded['codecompanion.strategies.chat.memory.helpers'] = {
      add_context = function(processed, chat)
        _G.__memory_processed = processed
        _G.__memory_chat = chat
      end
    }
  ]]))

  -- Use a rule as a table to include a parser field
  child.lua(string.format(
    [[
    local mem = require("codecompanion.strategies.chat.memory.init")
    mem.init({
      name = "test2",
      rules = { { path = %q, parser = "markdown" } }
    }):make({ id = "chat-2" })
  ]],
    tmp2
  ))

  local processed2 = child.lua("return _G.__memory_processed")
  local captured_chat2 = child.lua("return _G.__memory_chat")
  local expected_filename2 = child.lua("return vim.fn.fnamemodify(..., ':t')", { tmp2 })

  h.eq(type(processed2), "table")
  h.eq(#processed2, 1)
  h.eq(processed2[1].content, content2 .. "\n")
  h.eq(processed2[1].filename, expected_filename2)
  h.eq(processed2[1].parser, "markdown")
  h.eq(captured_chat2.id, "chat-2")
end

return T
