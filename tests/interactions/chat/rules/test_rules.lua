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

T["Rules:make()"] = new_set({})

T["Rules:make()"]["with string file (no parser)"] = function()
  local tmp = child.lua("return vim.fn.tempname()")
  local content = "plain rules content"
  child.fn.writefile({ content }, tmp)

  child.lua([[
    package.loaded['codecompanion.interactions.chat.rules.helpers'] = {
      add_context = function(processed, chat)
        _G.test_processed = processed
        _G.test_chat = chat
      end
    }
    package.loaded['codecompanion.config'] = { rules = { parsers = {} } }
  ]])

  child.lua(string.format(
    [[
    local Rules = require("codecompanion.interactions.chat.rules.init")
    Rules.new({ name = "literal_file_test", files = { %q } }):make({ chat = { id = "test_chat" } })
  ]],
    tmp
  ))

  local processed = child.lua("return _G.test_processed")
  local chat = child.lua("return _G.test_chat")
  local expected_filename = child.lua("return vim.fn.fnamemodify(..., ':t')", { tmp })
  local expected_path = child.lua("return vim.fs.normalize(...)", { tmp })

  h.eq(type(processed), "table")
  h.eq(#processed, 1)
  h.eq(processed[1].content, content .. "\n")
  h.eq(processed[1].filename, expected_filename)
  h.eq(processed[1].path, expected_path)
  h.eq(chat.id, "test_chat")
end

T["Rules:make()"]["applies parser when provided at file level"] = function()
  local tmp = child.lua("return vim.fn.tempname()")
  local content = "to be parsed"
  child.fn.writefile({ content }, tmp)

  child.lua([[
    package.loaded['codecompanion.config'] = {
      rules = {
        parsers = {
          prefix = { content = function(p) return "PFX:" .. (p.content or "") end }
        }
      }
    }
    package.loaded['codecompanion.interactions.chat.rules.helpers'] = {
      add_context = function(processed, chat)
        _G.test_processed = processed
        _G.test_chat = chat
      end
    }
  ]])

  child.lua(string.format(
    [[
    local Rules = require("codecompanion.interactions.chat.rules.init")
    Rules.new({
      name = "parser_test",
      files = { { path = %q, parser = "prefix" } },
    }):make({ chat = { id = "test_chat" } })
  ]],
    tmp
  ))

  local processed = child.lua("return _G.test_processed")
  local chat = child.lua("return _G.test_chat")

  h.eq(type(processed), "table")
  h.eq(#processed, 1)
  h.eq(processed[1].content, content .. "\n")
  h.eq(chat.id, "test_chat")
end

T["Rules:make()"]["with directory file (no parser)"] = function()
  local tmpdir = child.lua("return vim.fn.tempname()")
  child.fn.mkdir(tmpdir)
  local f1 = vim.fs.joinpath(tmpdir, "one.txt")
  local f2 = vim.fs.joinpath(tmpdir, "two.md")
  child.fn.writefile({ "first file" }, f1)
  child.fn.writefile({ "second file" }, f2)

  child.lua([[
    package.loaded['codecompanion.interactions.chat.rules.helpers'] = {
      add_context = function(processed, chat)
        _G.test_processed = processed
        _G.test_chat = chat
      end
    }
    package.loaded['codecompanion.config'] = { rules = { parsers = {} } }
  ]])

  child.lua(string.format(
    [[
    local Rules = require("codecompanion.interactions.chat.rules.init")
    Rules.new({ name = "directory_scan_test", files = { %q } }):make({ chat = { id = "test_chat" } })
  ]],
    tmpdir
  ))

  local processed = child.lua("return _G.test_processed")
  local chat = child.lua("return _G.test_chat")

  h.eq(type(processed), "table")
  h.eq(#processed, 2)

  local names = {}
  for i = 1, #processed do
    names[i] = processed[i].filename
  end
  table.sort(names)

  h.eq(names, { "one.txt", "two.md" })
  h.eq(chat.id, "test_chat")
end

T["Rules:make()"]["with glob pattern"] = function()
  local tmpdir = child.lua("return vim.fn.tempname()")
  child.fn.mkdir(tmpdir)
  local f1 = vim.fs.joinpath(tmpdir, "alpha.md")
  local f2 = vim.fs.joinpath(tmpdir, "beta.txt")
  child.fn.writefile({ "alpha" }, f1)
  child.fn.writefile({ "beta" }, f2)

  child.lua([[
    package.loaded['codecompanion.interactions.chat.rules.helpers'] = {
      add_context = function(processed, chat)
        _G.test_processed = processed
        _G.test_chat = chat
      end
    }
    package.loaded['codecompanion.config'] = { rules = { parsers = {} } }
  ]])

  child.lua(string.format(
    [[
    local Rules = require("codecompanion.interactions.chat.rules.init")
    Rules.new({ name = "glob_pattern_test", files = { %q } }):make({ chat = { id = "test_chat" } })
  ]],
    tmpdir .. "/*"
  ))

  local processed = child.lua("return _G.test_processed")
  local chat = child.lua("return _G.test_chat")

  h.eq(type(processed), "table")
  h.eq(#processed, 2)

  local names = {}
  for i = 1, #processed do
    names[i] = processed[i].filename
  end
  table.sort(names)

  h.eq(names, { "alpha.md", "beta.txt" })
  h.eq(chat.id, "test_chat")
end

T["Rules:make()"]["with directory and file patterns"] = function()
  local tmpdir = child.lua("return vim.fn.tempname()")
  child.fn.mkdir(tmpdir)
  local f1 = vim.fs.joinpath(tmpdir, ".clinerules")
  local f2 = vim.fs.joinpath(tmpdir, ".cursorrules")
  local f3 = vim.fs.joinpath(tmpdir, "README.md")
  local f4 = vim.fs.joinpath(tmpdir, "test.txt")
  child.fn.writefile({ "cline rules" }, f1)
  child.fn.writefile({ "cursor rules" }, f2)
  child.fn.writefile({ "readme" }, f3)
  child.fn.writefile({ "test" }, f4)

  child.lua([[
    package.loaded['codecompanion.interactions.chat.rules.helpers'] = {
      add_context = function(processed, chat)
        _G.test_processed = processed
        _G.test_chat = chat
      end
    }
    package.loaded['codecompanion.config'] = { rules = { parsers = {} } }
  ]])

  child.lua(string.format(
    [[
    local Rules = require("codecompanion.interactions.chat.rules.init")
    Rules.new({
      name = "pattern_filter_test",
      files = {
        { path = %q, files = { ".clinerules", ".cursorrules", "*.md" } }
      }
    }):make({ chat = { id = "test_chat" } })
  ]],
    tmpdir
  ))

  local processed = child.lua("return _G.test_processed")
  local chat = child.lua("return _G.test_chat")

  h.eq(type(processed), "table")
  h.eq(#processed, 3)

  local names = {}
  for i = 1, #processed do
    names[i] = processed[i].filename
  end
  table.sort(names)

  h.eq(names, { ".clinerules", ".cursorrules", "README.md" })
  h.eq(chat.id, "test_chat")
end

T["Rules:make()"]["with directory and files patterns deduplicates"] = function()
  local tmpdir = child.lua("return vim.fn.tempname()")
  child.fn.mkdir(tmpdir)
  local f1 = vim.fs.joinpath(tmpdir, "CLAUDE.md")
  child.fn.writefile({ "claude rules" }, f1)

  child.lua([[
    package.loaded['codecompanion.interactions.chat.rules.helpers'] = {
      add_context = function(processed, chat)
        _G.test_processed = processed
        _G.test_chat = chat
      end
    }
    package.loaded['codecompanion.config'] = { rules = { parsers = {} } }
  ]])

  child.lua(string.format(
    [[
    local Rules = require("codecompanion.interactions.chat.rules.init")
    Rules.new({
      name = "deduplication_test",
      files = {
        { path = %q, files = "*.md" },
        %q
      }
    }):make({ chat = { id = "test_chat" } })
  ]],
    tmpdir,
    f1
  ))

  local processed = child.lua("return _G.test_processed")
  local chat = child.lua("return _G.test_chat")

  h.eq(type(processed), "table")
  h.eq(#processed, 1)
  h.eq(processed[1].filename, "CLAUDE.md")
  h.eq(chat.id, "test_chat")
end

T["Rules:make()"]["integration: rules is added to a real chat messages stack"] = function()
  local tmp = child.lua("return vim.fn.tempname()")
  local content = "integration rules content"
  child.fn.writefile({ content }, tmp)

  child.lua(string.format(
    [[
    local h = require("tests.helpers")
    local cc = h.setup_plugin()
    local config = require("codecompanion.config")

    config.rules = vim.tbl_deep_extend("force", config.rules or {}, {
      default = {
        description = "integration default",
        files = { %q },
        is_preset = true,
      },
      parsers = {},
      opts = {
        chat = {
          enabled = true,
          default_rules = "default",
        },
        show_presets = true,
      },
    })

    _G.integration_chat = cc.chat()
    _G.integration_messages = _G.integration_chat and _G.integration_chat.messages or nil
  ]],
    tmp
  ))

  local messages = child.lua_get([[_G.integration_messages]])
  local last_message = messages[#messages]

  h.eq(#messages, 2)
  h.eq(last_message._meta.tag, "rules")
  h.eq(last_message.context.id, "<rules>" .. vim.fs.normalize(tmp) .. "</rules>")
  h.eq(last_message.content, content .. "\n")
end

T["add_files_or_buffers() prevents duplicate files from being added"] = function()
  local tmp1 = child.lua("return vim.fn.tempname()")
  local tmp2 = child.lua("return vim.fn.tempname()")
  child.fn.writefile({ "first file content" }, tmp1)
  child.fn.writefile({ "second file content" }, tmp2)

  child.lua(string.format(
    [[
    local h = require("tests.helpers")
    h.setup_plugin()

    local chat_helpers = require("codecompanion.interactions.chat.helpers")
    local rules_helpers = require("codecompanion.interactions.chat.rules.helpers")

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

    local files = { %q, %q, %q }
    rules_helpers.add_files_or_buffers(files, chat)

    _G.duplicate_messages = chat.messages
  ]],
    tmp1,
    tmp2,
    tmp1
  ))

  local messages = child.lua_get([[_G.duplicate_messages]])

  h.eq(#messages, 2)

  local has_tmp1 = false
  local has_tmp2 = false
  for _, msg in ipairs(messages) do
    if msg.context and msg.context.id then
      local path = msg.context.id:match("<file>(.-)</file>")
      if path then
        local abs_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
        if abs_path == vim.fs.normalize(tmp1) then
          has_tmp1 = true
        elseif abs_path == vim.fs.normalize(tmp2) then
          has_tmp2 = true
        end
      end
    end
  end

  h.eq(has_tmp1, true)
  h.eq(has_tmp2, true)
end

T["add_context() prevents duplicate rules context from being added"] = function()
  child.lua([[
    local h = require("tests.helpers")
    h.setup_plugin()

    local rules_helpers = require("codecompanion.interactions.chat.rules.helpers")
    local chat_helpers = require("codecompanion.interactions.chat.helpers")

    local has_context_call_count = 0
    local original_has_context = chat_helpers.has_context
    chat_helpers.has_context = function(id, messages)
      has_context_call_count = has_context_call_count + 1
      return has_context_call_count > 1
    end

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

    local files = {
      { name = "file1.txt", content = "content 1", path = "/tmp/file1.txt" },
      { name = "file1.txt", content = "content 1", path = "/tmp/file1.txt" },
    }

    rules_helpers.add_context(files, chat)

    _G.context_messages = chat.messages
    _G.context_call_count = has_context_call_count
  ]])

  local messages = child.lua_get([[_G.context_messages]])
  local call_count = child.lua_get([[_G.context_call_count]])

  h.eq(#messages, 1)
  h.eq(call_count, 2)
end

return T
