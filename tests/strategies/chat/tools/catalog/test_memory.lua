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
        _G.MEMORY_DIR = 'memories'
        _G.MEMORY_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.MEMORY_DIR)

        -- Create test directory structure
        vim.fn.mkdir(_G.MEMORY_DIR_ABSOLUTE, 'p')

        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        -- Change to the temporary directory
        vim.uv.chdir(_G.TEST_CWD)
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

T["view"] = new_set()

T["view"]["can view empty directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_1",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories"
        })
      },
    }

    -- Execute the tool and capture result
    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.expect_match(output.data, "Directory: /memories")
  h.expect_match(output.data, "%(empty%)")
end

T["view"]["can view directory with files"] = function()
  child.lua([[
    -- Create some test files
    local test_file_1 = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test1.txt")
    local test_file_2 = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test2.txt")
    vim.fn.writefile({"Hello"}, test_file_1)
    vim.fn.writefile({"World"}, test_file_2)

    local tool_call = {
      id = "test_call_2",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.expect_match(output.data, "Directory: /memories")
  h.expect_match(output.data, "test1%.txt")
  h.expect_match(output.data, "test2%.txt")
end

T["view"]["can view file content"] = function()
  child.lua([[
    -- Create a test file
    local test_file = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test.txt")
    vim.fn.writefile({"Line 1", "Line 2", "Line 3"}, test_file)

    local tool_call = {
      id = "test_call_3",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/test.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.eq(output.data, "Line 1\nLine 2\nLine 3\n")
end

T["view"]["can view file content with line range"] = function()
  child.lua([[
    -- Create a test file
    local test_file = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "test.txt")
    vim.fn.writefile({"Line 1", "Line 2", "Line 3", "Line 4", "Line 5"}, test_file)

    local tool_call = {
      id = "test_call_4",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/test.txt",
          view_range = {2, 4}
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "success")
  h.eq(output.data, "Line 2\nLine 3\nLine 4")
end

T["view"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_5",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/etc/passwd"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["view"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_6",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/../etc/passwd"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the memories directory")
end

T["view"]["handles non-existent path"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_7",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "view",
          path = "/memories/nonexistent.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")

  h.eq(output.status, "error")
  h.expect_match(output.data, "Path does not exist")
end

T["create"] = new_set()

T["create"]["can create a file"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_8",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/new_file.txt",
          file_text = "Hello, World!"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Created file: /memories/new_file.txt")

  -- Verify file was created
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new_file.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Hello, World!" })
end

T["create"]["can create a file with multiple lines"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_9",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/multi_line.txt",
          file_text = "Line 1\nLine 2\nLine 3"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file content
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multi_line.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["create"]["can create a file in a subdirectory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_10",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/subdir/nested_file.txt",
          file_text = "Nested content"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file was created in subdirectory
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir", "nested_file.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Nested content" })
end

T["create"]["can overwrite an existing file"] = function()
  child.lua([[
    -- Create initial file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "existing.txt")
    vim.fn.writefile({"Old content"}, file_path)

    local tool_call = {
      id = "test_call_11",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/existing.txt",
          file_text = "New content"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file was overwritten
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "existing.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "New content" })
end

T["create"]["can create an empty file"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_12",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/empty.txt",
          file_text = ""
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify empty file exists
  local exists = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty.txt")
    return vim.uv.fs_stat(file_path) ~= nil
  ]])
  h.eq(exists, true)
end

T["create"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_13",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/tmp/evil.txt",
          file_text = "Should not be created"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["create"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_14",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "create",
          path = "/memories/../tmp/evil.txt",
          file_text = "Should not be created"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua_get("_G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the memories directory")
end

return T
