local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Setup test directory structure
        _G.TEST_CWD = vim.fn.tempname()
        _G.TEST_DIR = 'tests/stubs/get_diagnostics'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.TEST_DIR)

        _G.TEST_TMPFILE = "cc_diagnostics_test.txt"
        _G.TEST_TMPFILE_ABSOLUTE = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, _G.TEST_TMPFILE)

        -- Create test directory structure
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE, 'p')

        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.fn.delete, _G.TEST_CWD, 'rf')
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["returns no diagnostics for a clean file"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)

    -- Create a simple file and load it into a buffer
    local ok = vim.fn.writefile({ "hello world" }, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    -- Pre-load the buffer so the tool doesn't need to call bufload
    local bufnr = vim.fn.bufadd(_G.TEST_TMPFILE_ABSOLUTE)
    vim.fn.bufload(bufnr)

    local tool = {
      {
        ["function"] = {
          name = "get_diagnostics",
          arguments = string.format('{"filepath": "%s"}', _G.TEST_TMPFILE_ABSOLUTE)
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("No diagnostics found", output)
end

T["returns diagnostics when they exist"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)

    -- Create a file and load it into a buffer
    local ok = vim.fn.writefile({ "hello world", "another line" }, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    local bufnr = vim.fn.bufadd(_G.TEST_TMPFILE_ABSOLUTE)
    vim.fn.bufload(bufnr)

    -- Manually set diagnostics on the buffer
    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, bufnr, {
      {
        lnum = 0,
        end_lnum = 0,
        col = 0,
        end_col = 5,
        severity = vim.diagnostic.severity.ERROR,
        message = "Undefined variable",
      },
    })

    local tool = {
      {
        ["function"] = {
          name = "get_diagnostics",
          arguments = string.format('{"filepath": "%s"}', _G.TEST_TMPFILE_ABSOLUTE)
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("1 found", output)
  h.expect_contains("ERROR", output)
  h.expect_contains("Undefined variable", output)
end

T["filters diagnostics by severity"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)

    local ok = vim.fn.writefile({ "hello world", "another line" }, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    local bufnr = vim.fn.bufadd(_G.TEST_TMPFILE_ABSOLUTE)
    vim.fn.bufload(bufnr)

    -- Set diagnostics with different severities
    local ns = vim.api.nvim_create_namespace("test_diagnostics_severity")
    vim.diagnostic.set(ns, bufnr, {
      {
        lnum = 0,
        end_lnum = 0,
        col = 0,
        end_col = 5,
        severity = vim.diagnostic.severity.ERROR,
        message = "This is an error",
      },
      {
        lnum = 1,
        end_lnum = 1,
        col = 0,
        end_col = 5,
        severity = vim.diagnostic.severity.HINT,
        message = "This is a hint",
      },
    })

    -- Request only ERROR severity
    local tool = {
      {
        ["function"] = {
          name = "get_diagnostics",
          arguments = string.format('{"filepath": "%s", "severity": "ERROR"}', _G.TEST_TMPFILE_ABSOLUTE)
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("1 found", output)
  h.expect_contains("This is an error", output)
end

T["handles empty filepath"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "get_diagnostics",
          arguments = '{"filepath": ""}'
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("required and cannot be empty", output)
end

T["returns multiple diagnostics with code context"] = function()
  child.lua([[
    vim.uv.chdir(_G.TEST_CWD)

    local ok = vim.fn.writefile({ "line one", "line two", "line three" }, _G.TEST_TMPFILE_ABSOLUTE)
    assert(ok == 0)

    local bufnr = vim.fn.bufadd(_G.TEST_TMPFILE_ABSOLUTE)
    vim.fn.bufload(bufnr)

    local ns = vim.api.nvim_create_namespace("test_diagnostics_multi")
    vim.diagnostic.set(ns, bufnr, {
      {
        lnum = 0,
        end_lnum = 0,
        col = 0,
        end_col = 4,
        severity = vim.diagnostic.severity.ERROR,
        message = "First error",
      },
      {
        lnum = 2,
        end_lnum = 2,
        col = 0,
        end_col = 5,
        severity = vim.diagnostic.severity.WARN,
        message = "A warning here",
      },
    })

    local tool = {
      {
        ["function"] = {
          name = "get_diagnostics",
          arguments = string.format('{"filepath": "%s"}', _G.TEST_TMPFILE_ABSOLUTE)
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("2 found", output)
  h.expect_contains("First error", output)
  h.expect_contains("A warning here", output)
  h.expect_contains("WARNING", output)
end

return T
