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

T["str_replace"] = new_set()

T["str_replace"]["can replace text in a file"] = function()
  child.lua([[
    -- Create a file with initial content
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "replace_test.txt")
    vim.fn.writefile({"Hello World", "This is a test"}, file_path)

    local tool_call = {
      id = "test_call_15",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/replace_test.txt",
          old_str = "Hello World",
          new_str = "Goodbye World"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Replaced text in file: /memories/replace_test.txt")

  -- Verify the replacement
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "replace_test.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Goodbye World", "This is a test" })
end

T["str_replace"]["replaces only first occurrence"] = function()
  child.lua([[
    -- Create a file with duplicate content
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "duplicate.txt")
    vim.fn.writefile({"foo bar foo", "foo baz"}, file_path)

    local tool_call = {
      id = "test_call_16",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/duplicate.txt",
          old_str = "foo",
          new_str = "bar"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify only first occurrence was replaced
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "duplicate.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "bar bar foo", "foo baz" })
end

T["str_replace"]["can replace multiline text"] = function()
  child.lua([[
    -- Create a file with multiline content
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline.txt")
    vim.fn.writefile({"Line 1", "Line 2", "Line 3"}, file_path)

    local tool_call = {
      id = "test_call_17",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/multiline.txt",
          old_str = "Line 2",
          new_str = "Modified Line 2"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Modified Line 2", "Line 3" })
end

T["str_replace"]["handles special characters"] = function()
  child.lua([[
    -- Create a file with special characters
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "special.txt")
    vim.fn.writefile({"Test: $var = 100%"}, file_path)

    local tool_call = {
      id = "test_call_18",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/special.txt",
          old_str = "$var = 100%",
          new_str = "$var = 50%"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "special.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Test: $var = 50%" })
end

T["str_replace"]["fails when string not found"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "not_found.txt")
    vim.fn.writefile({"Hello World"}, file_path)

    local tool_call = {
      id = "test_call_19",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/not_found.txt",
          old_str = "Nonexistent String",
          new_str = "New String"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "String not found in file")
end

T["str_replace"]["fails when file does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_20",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/nonexistent.txt",
          old_str = "old",
          new_str = "new"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "File does not exist")
end

T["str_replace"]["fails when path is a directory"] = function()
  child.lua([[
    -- Create a subdirectory
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir")
    vim.fn.mkdir(dir_path, "p")

    local tool_call = {
      id = "test_call_21",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/memories/subdir",
          old_str = "old",
          new_str = "new"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Cannot perform str_replace on a directory")
end

T["str_replace"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_22",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "str_replace",
          path = "/tmp/file.txt",
          old_str = "old",
          new_str = "new"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["insert"] = new_set()

T["insert"]["can insert text at beginning"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "insert_test.txt")
    vim.fn.writefile({"Line 2", "Line 3"}, file_path)

    local tool_call = {
      id = "test_call_23",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/insert_test.txt",
          insert_line = 1,
          insert_text = "Line 1"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Inserted text in file: /memories/insert_test.txt")

  -- Verify the insertion
  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "insert_test.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["can insert text in middle"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "middle.txt")
    vim.fn.writefile({"Line 1", "Line 3"}, file_path)

    local tool_call = {
      id = "test_call_24",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/middle.txt",
          insert_line = 2,
          insert_text = "Line 2"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "middle.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["can insert text at end"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "end.txt")
    vim.fn.writefile({"Line 1", "Line 2"}, file_path)

    local tool_call = {
      id = "test_call_25",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/end.txt",
          insert_line = 3,
          insert_text = "Line 3"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "end.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["can insert into empty file"] = function()
  child.lua([[
    -- Create empty file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_insert.txt")
    vim.fn.writefile({}, file_path)

    local tool_call = {
      id = "test_call_26",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/empty_insert.txt",
          insert_line = 1,
          insert_text = "First line"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_insert.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "First line" })
end

T["insert"]["can insert multiline text"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline_insert.txt")
    vim.fn.writefile({"Line 1"}, file_path)

    local tool_call = {
      id = "test_call_27",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/multiline_insert.txt",
          insert_line = 2,
          insert_text = "Line 2\nLine 3"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  local content = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "multiline_insert.txt")
    return vim.fn.readfile(file_path)
  ]])
  h.eq(content, { "Line 1", "Line 2", "Line 3" })
end

T["insert"]["fails with invalid line number (too low)"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "invalid_low.txt")
    vim.fn.writefile({"Line 1"}, file_path)

    local tool_call = {
      id = "test_call_28",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/invalid_low.txt",
          insert_line = 0,
          insert_text = "Should fail"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Invalid line number")
end

T["insert"]["fails with invalid line number (too high)"] = function()
  child.lua([[
    -- Create a file with 2 lines
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "invalid_high.txt")
    vim.fn.writefile({"Line 1", "Line 2"}, file_path)

    local tool_call = {
      id = "test_call_29",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/invalid_high.txt",
          insert_line = 10,
          insert_text = "Should fail"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Invalid line number")
end

T["insert"]["fails when file does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_30",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/nonexistent.txt",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "File does not exist")
end

T["insert"]["fails when path is a directory"] = function()
  child.lua([[
    -- Create a subdirectory
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "insert_dir")
    vim.fn.mkdir(dir_path, "p")

    local tool_call = {
      id = "test_call_31",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/memories/insert_dir",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Cannot perform insert on a directory")
end

T["insert"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_32",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/tmp/file.txt",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["insert"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_32",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "insert",
          path = "/tmp/file.txt",
          insert_line = 1,
          insert_text = "Should fail"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["delete"] = new_set()

T["delete"]["can delete a file"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "delete_me.txt")
    vim.fn.writefile({"Content to delete"}, file_path)

    local tool_call = {
      id = "test_call_33",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/delete_me.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Deleted: /memories/delete_me.txt")

  -- Verify file was deleted
  local exists = child.lua([[
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "delete_me.txt")
    return vim.uv.fs_stat(file_path) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["can delete an empty directory"] = function()
  child.lua([[
    -- Create an empty directory
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_dir")
    vim.fn.mkdir(dir_path, "p")

    local tool_call = {
      id = "test_call_34",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/empty_dir"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify directory was deleted
  local exists = child.lua([[
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "empty_dir")
    return vim.uv.fs_stat(dir_path) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["can delete a directory with files"] = function()
  child.lua([[
    -- Create a directory with files
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "dir_with_files")
    vim.fn.mkdir(dir_path, "p")
    vim.fn.writefile({"File 1"}, vim.fs.joinpath(dir_path, "file1.txt"))
    vim.fn.writefile({"File 2"}, vim.fs.joinpath(dir_path, "file2.txt"))

    local tool_call = {
      id = "test_call_35",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/dir_with_files"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify directory was deleted recursively
  local exists = child.lua([[
    local dir_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "dir_with_files")
    return vim.uv.fs_stat(dir_path) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["can delete nested directories"] = function()
  child.lua([[
    -- Create nested directory structure
    local parent_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "parent")
    local child_dir = vim.fs.joinpath(parent_dir, "child")
    vim.fn.mkdir(child_dir, "p")
    vim.fn.writefile({"Nested file"}, vim.fs.joinpath(child_dir, "nested.txt"))

    local tool_call = {
      id = "test_call_36",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/parent"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify entire structure was deleted
  local exists = child.lua([[
    local parent_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "parent")
    return vim.uv.fs_stat(parent_dir) ~= nil
  ]])
  h.eq(exists, false)
end

T["delete"]["fails when file does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_37",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/nonexistent.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path does not exist")
end

T["delete"]["fails when trying to delete root memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_38",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Cannot delete the root memory directory")
end

T["delete"]["rejects path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_39",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/tmp/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["delete"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_40",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/../tmp/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the memories directory")
end

T["delete"]["rejects directory traversal"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_40",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "delete",
          path = "/memories/../tmp/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the memories directory")
end

T["rename"] = new_set()

T["rename"]["can rename a file"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_name.txt")
    vim.fn.writefile({"File content"}, file_path)

    local tool_call = {
      id = "test_call_41",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/old_name.txt",
          new_path = "/memories/new_name.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")
  h.expect_match(output.data, "Renamed /memories/old_name.txt to /memories/new_name.txt")

  -- Verify old file doesn't exist
  local old_exists = child.lua([[
    local old_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_name.txt")
    return vim.uv.fs_stat(old_path) ~= nil
  ]])
  h.eq(old_exists, false)

  -- Verify new file exists with same content
  local content = child.lua([[
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new_name.txt")
    return vim.fn.readfile(new_path)
  ]])
  h.eq(content, { "File content" })
end

T["rename"]["can rename a directory"] = function()
  child.lua([[
    -- Create a directory with a file
    local old_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_dir")
    vim.fn.mkdir(old_dir, "p")
    vim.fn.writefile({"Content"}, vim.fs.joinpath(old_dir, "file.txt"))

    local tool_call = {
      id = "test_call_42",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/old_dir",
          new_path = "/memories/new_dir"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify old directory doesn't exist
  local old_exists = child.lua([[
    local old_dir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old_dir")
    return vim.uv.fs_stat(old_dir) ~= nil
  ]])
  h.eq(old_exists, false)

  -- Verify new directory exists with file
  local file_exists = child.lua([[
    local new_file = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new_dir", "file.txt")
    return vim.uv.fs_stat(new_file) ~= nil
  ]])
  h.eq(file_exists, true)
end

T["rename"]["can move file to subdirectory"] = function()
  child.lua([[
    -- Create a file and subdirectory
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local subdir = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir")
    vim.fn.mkdir(subdir, "p")

    local tool_call = {
      id = "test_call_43",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/memories/subdir/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file was moved
  local old_exists = child.lua([[
    local old_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    return vim.uv.fs_stat(old_path) ~= nil
  ]])
  h.eq(old_exists, false)

  local new_exists = child.lua([[
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "subdir", "file.txt")
    return vim.uv.fs_stat(new_path) ~= nil
  ]])
  h.eq(new_exists, true)
end

T["rename"]["creates parent directories if needed"] = function()
  child.lua([[
    -- Create a file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local tool_call = {
      id = "test_call_44",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/memories/new/nested/path/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "success")

  -- Verify file exists in new location
  local new_exists = child.lua([[
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new", "nested", "path", "file.txt")
    return vim.uv.fs_stat(new_path) ~= nil
  ]])
  h.eq(new_exists, true)
end

T["rename"]["fails when source does not exist"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_45",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/nonexistent.txt",
          new_path = "/memories/new.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Source path does not exist")
end

T["rename"]["fails when destination already exists"] = function()
  child.lua([[
    -- Create both files
    local old_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "old.txt")
    local new_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "new.txt")
    vim.fn.writefile({"Old"}, old_path)
    vim.fn.writefile({"New"}, new_path)

    local tool_call = {
      id = "test_call_46",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/old.txt",
          new_path = "/memories/new.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Destination path already exists")
end

T["rename"]["rejects old_path outside memory directory"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_47",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/tmp/file.txt",
          new_path = "/memories/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["rename"]["rejects new_path outside memory directory"] = function()
  child.lua([[
    -- Create source file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local tool_call = {
      id = "test_call_48",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/tmp/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Path must start with /memories")
end

T["rename"]["rejects directory traversal in old_path"] = function()
  child.lua([[
    local tool_call = {
      id = "test_call_49",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/../tmp/file.txt",
          new_path = "/memories/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the memories directory")
end

T["rename"]["rejects directory traversal in new_path"] = function()
  child.lua([[
    -- Create source file
    local file_path = vim.fs.joinpath(_G.MEMORY_DIR_ABSOLUTE, "file.txt")
    vim.fn.writefile({"Content"}, file_path)

    local tool_call = {
      id = "test_call_50",
      type = "function",
      ["function"] = {
        name = "memory",
        arguments = vim.json.encode({
          command = "rename",
          old_path = "/memories/file.txt",
          new_path = "/memories/../tmp/file.txt"
        })
      },
    }

    local catalog = require("codecompanion.strategies.chat.tools.catalog.memory")
    local args = vim.json.decode(tool_call["function"].arguments)
    _G.result = catalog.cmds[1](catalog, args)
  ]])

  local output = child.lua("return _G.result")
  h.eq(output.status, "error")
  h.expect_match(output.data, "Must reside within the memories directory")
end

return T
