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

T["Memory.make() with string rule (no parser)"] = function()
  local tmp = child.lua("return vim.fn.tempname()")
  local content = "plain memory content"
  child.fn.writefile({ content }, tmp)

  -- Monkey-patch helpers to capture processed data and chat
  child.lua([[
    package.loaded['codecompanion.strategies.chat.memory.helpers'] = {
      add_context = function(processed, chat)
        _G.__mem_processed = processed
        _G.__mem_chat = chat
      end
    }
    -- Minimal config to avoid nil in parsers module
    package.loaded['codecompanion.config'] = { memory = { parsers = {} } }
  ]])

  child.lua(string.format(
    [[
    local Memory = require("codecompanion.strategies.chat.memory.init")
    Memory.init({ name = "t1", rules = { %q } }):make({ id = "c-1" })
  ]],
    tmp
  ))

  local processed = child.lua("return _G.__mem_processed")
  local chat = child.lua("return _G.__mem_chat")
  local expected_filename = child.lua("return vim.fn.fnamemodify(..., ':t')", { tmp })
  local expected_path = child.lua("return vim.fs.normalize(...)", { tmp })

  h.eq(type(processed), "table")
  h.eq(#processed, 1)
  -- file read returns content plus newline; code earlier expected content .. "\n"
  h.eq(processed[1].content, content .. "\n")
  h.eq(processed[1].filename, expected_filename)
  h.eq(processed[1].path, expected_path)
  h.eq(chat.id, "c-1")
end

T["Memory.make() applies parser when provided at rule level"] = function()
  local tmp = child.lua("return vim.fn.tempname()")
  local content = "to be parsed"
  child.fn.writefile({ content }, tmp)

  child.lua([[
    package.loaded['codecompanion.config'] = {
      memory = {
        parsers = {
          prefix = { content = function(p) return "PFX:" .. (p.content or "") end }
        }
      }
    }

    package.loaded['codecompanion.strategies.chat.memory.helpers'] = {
      add_context = function(processed, chat)
        _G.__mem2_processed = processed
        _G.__mem2_chat = chat
      end
    }
  ]])

  child.lua(string.format(
    [[
    local Memory = require("codecompanion.strategies.chat.memory.init")
    Memory.init({
      name = "t2",
      rules = { { path = %q, parser = "prefix" } },
    }):make({ id = "c-2" })
  ]],
    tmp
  ))

  local processed = child.lua("return _G.__mem2_processed")
  local chat = child.lua("return _G.__mem2_chat")

  h.eq(type(processed), "table")
  h.eq(#processed, 1)
  h.eq(processed[1].content, "PFX:" .. content .. "\n")
  h.eq(chat.id, "c-2")
end

return T
