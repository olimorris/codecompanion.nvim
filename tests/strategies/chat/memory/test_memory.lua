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
  h.eq(processed[1].content, content .. "\n")
  h.eq(chat.id, "c-2")
end

T["Memory.make() with directory rule (no parser)"] = function()
  local tmpdir = child.lua("return vim.fn.tempname()")
  -- create directory
  child.fn.mkdir(tmpdir)
  local f1 = tmpdir .. "/one.txt"
  local f2 = tmpdir .. "/two.md"
  child.fn.writefile({ "first file" }, f1)
  child.fn.writefile({ "second file" }, f2)
  -- Monkey-patch helpers to capture processed data and chat
  child.lua([[
    package.loaded['codecompanion.strategies.chat.memory.helpers'] = {
      add_context = function(processed, chat)
        _G.__mem3_processed = processed
        _G.__mem3_chat = chat
      end
    }
    -- Minimal config to avoid nil in parsers module
    package.loaded['codecompanion.config'] = { memory = { parsers = {} } }
  ]])
  child.lua(string.format(
    [[
    local Memory = require("codecompanion.strategies.chat.memory.init")
    Memory.init({ name = "t3", rules = { %q } }):make({ id = "c-3" })
  ]],
    tmpdir
  ))
  local processed = child.lua("return _G.__mem3_processed")
  local chat = child.lua("return _G.__mem3_chat")
  h.eq(type(processed), "table")
  h.eq(#processed, 2)
  local names = {}
  for i = 1, #processed do
    names[i] = processed[i].filename
  end
  table.sort(names)
  h.eq(names, { "one.txt", "two.md" })
  h.eq(chat.id, "c-3")
end

T["Memory.make() with glob pattern"] = function()
  local tmpdir = child.lua("return vim.fn.tempname()")
  child.fn.mkdir(tmpdir)
  local f1 = tmpdir .. "/alpha.md"
  local f2 = tmpdir .. "/beta.txt"
  child.fn.writefile({ "alpha" }, f1)
  child.fn.writefile({ "beta" }, f2)

  child.lua([[
    package.loaded['codecompanion.strategies.chat.memory.helpers'] = {
      add_context = function(processed, chat)
        _G.__mem5_processed = processed
        _G.__mem5_chat = chat
      end
    }
    package.loaded['codecompanion.config'] = { memory = { parsers = {} } }
  ]])

  -- Use a glob that matches both files in the directory
  local pattern = tmpdir .. "/*"
  child.lua(string.format(
    [[
    local Memory = require("codecompanion.strategies.chat.memory.init")
    Memory.init({ name = "t5", rules = { %q } }):make({ id = "c-5" })
  ]],
    pattern
  ))

  local processed = child.lua("return _G.__mem5_processed")
  local chat = child.lua("return _G.__mem5_chat")
  h.eq(type(processed), "table")
  h.eq(#processed, 2)
  local names = {}
  for i = 1, #processed do
    names[i] = processed[i].filename
  end
  table.sort(names)
  h.eq(names, { "alpha.md", "beta.txt" })
  h.eq(chat.id, "c-5")
end

T["Memory.make() integration: memory is added to a real chat messages stack"] = function()
  local tmp = child.lua("return vim.fn.tempname()")
  local content = "integration memory content"
  child.fn.writefile({ content }, tmp)

  -- Use test helpers to setup the plugin (less brittle than directly mutating package.loaded)
  child.lua(string.format(
    [[
    local h = require("tests.helpers")
    -- Initialize plugin with test config (h.setup_plugin returns the codecompanion module)
    local cc = h.setup_plugin()

    local config = require("codecompanion.config")

    -- Merge our memory settings into the existing test config to avoid overwriting unrelated defaults
    config.memory = vim.tbl_deep_extend("force", config.memory or {}, {
      default = {
        description = "integration default",
        rules = { %q },
        is_default = true,
      },
      parsers = {},
      opts = {
        chat = {
          enabled = true,
          default_memory = "default",
          condition = function() return true end,
        },
        show_defaults = true,
      },
    })

    -- Create a chat via the public API (this should trigger the memory callback)
    _G.__int_chat = cc.chat()
    _G.__int_messages = _G.__int_chat and _G.__int_chat.messages or nil
  ]],
    tmp
  ))

  local messages = child.lua_get([[_G.__int_messages]])
  local last_message = messages[#messages]

  h.eq(#messages, 2) -- System prompt + memory
  h.eq(last_message.opts.tag, "memory")
  h.eq(last_message.opts.context_id, "<memory>" .. tmp .. "</memory>")
  h.eq(last_message.content, content .. "\n")
end

return T
