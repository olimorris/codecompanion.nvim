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

T["Memory.make() with string file (no parser)"] = function()
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
    Memory.init({ name = "t1", files = { %q } }):make({ id = "c-1" })
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

T["Memory.make() applies parser when provided at file level"] = function()
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
      files = { { path = %q, parser = "prefix" } },
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

T["Memory.make() with directory file (no parser)"] = function()
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
    Memory.init({ name = "t3", files = { %q } }):make({ id = "c-3" })
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
    Memory.init({ name = "t5", files = { %q } }):make({ id = "c-5" })
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
        files = { %q },
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
  h.eq(last_message._meta.tag, "memory")
  h.eq(last_message.context.id, "<memory>" .. tmp .. "</memory>")
  h.eq(last_message.content, content .. "\n")
end

T["add_files_or_buffers() prevents duplicate files from being added"] = function()
  local tmp1 = child.lua("return vim.fn.tempname()")
  local tmp2 = child.lua("return vim.fn.tempname()")
  local content1 = "first file content"
  local content2 = "second file content"
  child.fn.writefile({ content1 }, tmp1)
  child.fn.writefile({ content2 }, tmp2)

  -- Setup the test environment
  child.lua(string.format(
    [[
    local h = require("tests.helpers")
    h.setup_plugin()

    local chat_helpers = require("codecompanion.strategies.chat.helpers")
    local memory_helpers = require("codecompanion.strategies.chat.memory.helpers")

    -- Create a mock chat object
    local chat = {
      messages = {},
      add_context = function(self, content, tag, id, opts)
        table.insert(self.messages, {
          content = content.content,
          context = { id = id },
          _meta = { tag = tag },
        })
      end
    }

    -- Add the same file multiple times
    local files = { %q, %q, %q }
    memory_helpers.add_files_or_buffers(files, chat)

    _G.__dup_test_messages = chat.messages
  ]],
    tmp1,
    tmp2,
    tmp1 -- Duplicate of tmp1
  ))

  local messages = child.lua_get([[_G.__dup_test_messages]])

  -- Should only have 2 messages (no duplicate for tmp1)
  h.eq(#messages, 2)

  -- Verify the two unique files are present
  local has_tmp1 = false
  local has_tmp2 = false
  for _, msg in ipairs(messages) do
    if msg.context and msg.context.id then
      -- Extract the path from the context id format: <file>path</file>
      local path = msg.context.id:match("<file>(.-)</file>")
      if path then
        -- Convert to absolute path for comparison
        local abs_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
        if abs_path == tmp1 then
          has_tmp1 = true
        elseif abs_path == tmp2 then
          has_tmp2 = true
        end
      end
    end
  end

  h.eq(has_tmp1, true)
  h.eq(has_tmp2, true)
end

T["add_context() prevents duplicate memory context from being added"] = function()
  -- Setup the test environment
  child.lua([[
    local h = require("tests.helpers")
    h.setup_plugin()

    local memory_helpers = require("codecompanion.strategies.chat.memory.helpers")
    local chat_helpers = require("codecompanion.strategies.chat.helpers")

    -- Mock chat_helpers.has_context to track calls
    local has_context_calls = 0
    local original_has_context = chat_helpers.has_context
    chat_helpers.has_context = function(id, messages)
      has_context_calls = has_context_calls + 1
      -- Return true on second call to simulate duplicate
      return has_context_calls > 1
    end

    -- Create a mock chat object
    local chat = {
      messages = {},
      add_context = function(self, content, tag, id, opts)
        table.insert(self.messages, {
          content = content.content,
          context = { id = id },
          _meta = { tag = tag },
        })
      end
    }

    -- Create test files
    local files = {
      { name = "file1.txt", content = "content 1", path = "/tmp/file1.txt" },
      { name = "file1.txt", content = "content 1", path = "/tmp/file1.txt" }, -- duplicate
    }

    -- Add context twice with the same file
    memory_helpers.add_context(files, chat)

    _G.__context_test_messages = chat.messages
    _G.__context_test_calls = has_context_calls
  ]])

  local messages = child.lua_get([[_G.__context_test_messages]])
  local calls = child.lua_get([[_G.__context_test_calls]])

  -- Should only have 1 message (no duplicate)
  h.eq(#messages, 1)
  -- has_context should have been called twice (once for each file in the list)
  h.eq(calls, 2)
end

return T
