local files = require("codecompanion.utils.files")
local h = require("tests.helpers")
local log = require("codecompanion.utils.log")
local new_set = MiniTest.new_set

local T = new_set()

-- Test fixture directory
local test_dir = vim.fn.tempname()

T["Files utils"] = new_set({
  hooks = {
    pre_case = function()
      -- Create test directory structure
      vim.fn.mkdir(test_dir, "p")
    end,
    post_case = function()
      -- Cleanup test directory
      vim.fn.delete(test_dir, "rf")
    end,
  },
})

T["Files utils"]["create_dir_recursive"] = new_set()

T["Files utils"]["create_dir_recursive"]["can create a single directory"] = function()
  local dir_path = vim.fs.joinpath(test_dir, "single_dir")
  local success, err = files.create_dir_recursive(dir_path)

  h.eq(true, success)
  h.eq(nil, err)
  h.eq("directory", vim.uv.fs_stat(dir_path).type)
end

T["Files utils"]["create_dir_recursive"]["can create nested directories"] = function()
  local dir_path = vim.fs.joinpath(test_dir, "nested", "deep", "directory")
  local success, err = files.create_dir_recursive(dir_path)

  h.eq(true, success)
  h.eq(nil, err)
  h.eq("directory", vim.uv.fs_stat(dir_path).type)

  -- Verify all parent directories were created
  local nested_path = vim.fs.joinpath(test_dir, "nested")
  local deep_path = vim.fs.joinpath(test_dir, "nested", "deep")

  h.eq("directory", vim.uv.fs_stat(nested_path).type)
  h.eq("directory", vim.uv.fs_stat(deep_path).type)
end

T["Files utils"]["create_dir_recursive"]["handles existing directories gracefully"] = function()
  local dir_path = vim.fs.joinpath(test_dir, "existing_dir")

  -- Create directory first
  vim.fn.mkdir(dir_path, "p")
  h.eq("directory", vim.uv.fs_stat(dir_path).type)

  -- Try to create it again
  local success, err = files.create_dir_recursive(dir_path)

  h.eq(true, success)
  h.eq(nil, err)
  h.eq("directory", vim.uv.fs_stat(dir_path).type)
end

T["Files utils"]["create_dir_recursive"]["handles partially existing paths"] = function()
  local partial_path = vim.fs.joinpath(test_dir, "partial_existing")
  local full_path = vim.fs.joinpath(partial_path, "new_dir", "another_dir")

  -- Create first part of the path
  vim.fn.mkdir(partial_path, "p")
  h.eq("directory", vim.uv.fs_stat(partial_path).type)

  -- Create the rest
  local success, err = files.create_dir_recursive(full_path)

  h.eq(true, success)
  h.eq(nil, err)
  h.eq("directory", vim.uv.fs_stat(full_path).type)
end

T["Files utils"]["create_dir_recursive"]["handles root directory"] = function()
  -- Should handle root directory gracefully without error
  local success, err = files.create_dir_recursive("/")

  h.eq(true, success)
  h.eq(nil, err)
end

T["Files utils"]["create_dir_recursive"]["handles Windows root directory"] = function()
  if vim.fn.has("win32") ~= 1 then
    MiniTest.skip("Not on Windows")
  end

  local success, err = files.create_dir_recursive("C:\\")
  h.eq(true, success)
  h.eq(nil, err)
end

T["Files utils"]["create_dir_recursive"]["returns error for invalid paths"] = function()
  -- Try to create directory in a path that can't exist (using a file as parent)
  local file_path = vim.fs.joinpath(test_dir, "test_file.txt")
  local invalid_dir_path = vim.fs.joinpath(file_path, "invalid_dir")

  -- Create a file first
  local file = io.open(file_path, "w")
  if file then
    file:write("test content")
    file:close()
  end
  h.eq("file", vim.uv.fs_stat(file_path).type)

  -- Temporarily silence log.error for this specific test case
  local original_log_error = log.error
  local logged_messages_for_this_test = {}
  log.error = function(_, msg, ...)
    table.insert(logged_messages_for_this_test, string.format(msg, ...))
  end

  -- Try to create directory inside the file path
  local success, err = files.create_dir_recursive(invalid_dir_path)

  -- Restore original log.error
  log.error = original_log_error

  h.eq(false, success)
  h.expect.no_equality(nil, err)
  h.expect_contains("Failed to create directory", err) -- Check the returned error message
  h.expect_contains("create_dir_recursive:", logged_messages_for_this_test[1] or "")
end

T["Files utils"]["create_dir_recursive"]["logs errors properly"] = function()
  -- This test verifies that errors are logged
  local file_path = vim.fs.joinpath(test_dir, "log_test_file.txt")
  local invalid_dir_path = vim.fs.joinpath(file_path, "invalid_dir_for_log")

  -- Create a file first
  local file = io.open(file_path, "w")
  if file then
    file:write("test content")
    file:close()
  end

  -- Capture log messages
  local original_error = log.error
  local logged_messages = {}
  log.error = function(_, msg, ...)
    table.insert(logged_messages, string.format(msg, ...))
  end

  -- Try to create directory and expect error to be logged
  local success, err = files.create_dir_recursive(invalid_dir_path)

  -- Restore original log function
  log.error = original_error

  h.eq(false, success)
  h.expect.no_equality(nil, err)
  h.expect_contains("create_dir_recursive:", logged_messages[1] or "")
end

T["Files utils"]["get_mimetype"] = new_set()
T["Files utils"]["get_mimetype"]["can invoke `file`"] = function()
  local orig_system = vim.system
  local _cmd, _opts, _cb = nil, nil, nil
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmds, opts, cb)
    _cmd = cmds
    _opts = opts
    _cb = cb
    return {
      wait = function()
        return { code = 0, stdout = "some_file.txt: text/plain\n" }
      end,
    }
  end

  local _type = files.get_mimetype("some_file.txt")
  h.eq({ "file", "--mime-type", "some_file.txt" }, _cmd)
  h.eq("text/plain", _type)
  vim.system = orig_system
end

T["Files utils"]["get_mimetype"]["works without `file`"] = function()
  local orig_system = vim.system

  local _cmd, _opts, _cb = nil, nil, nil
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmds, opts, cb)
    _cmd = cmds
    _opts = opts
    _cb = cb
    return {
      wait = function()
        return { code = 1 }
      end,
    }
  end

  local _type = files.get_mimetype("some_file.png")
  h.eq({ "file", "--mime-type", "some_file.png" }, _cmd)
  h.eq("image/png", _type)
  vim.system = orig_system
end

T["Files utils"]["match_pattern"] = new_set()

T["Files utils"]["match_pattern"]["matches exact literal patterns"] = function()
  h.eq(true, files.match_pattern(".clinerules", ".clinerules"))
  h.eq(true, files.match_pattern("CLAUDE.md", "CLAUDE.md"))
  h.eq(true, files.match_pattern("test_file.lua", "test_file.lua"))
end

T["Files utils"]["match_pattern"]["rejects non-matching literal patterns"] = function()
  h.eq(false, files.match_pattern(".clinerules", ".cursorrules"))
  h.eq(false, files.match_pattern("CLAUDE.md", "claude.md"))
  h.eq(false, files.match_pattern("test.lua", "test.txt"))
end

T["Files utils"]["match_pattern"]["is case sensitive"] = function()
  h.eq(true, files.match_pattern("README.md", "README.md"))
  h.eq(false, files.match_pattern("readme.md", "README.md"))
  h.eq(false, files.match_pattern("CLAUDE.MD", "CLAUDE.md"))
end

T["Files utils"]["match_pattern"]["matches wildcard * patterns"] = function()
  h.eq(true, files.match_pattern("test.md", "*.md"))
  h.eq(true, files.match_pattern("CLAUDE.md", "*.md"))
  h.eq(true, files.match_pattern("file.txt", "*.txt"))
  h.eq(false, files.match_pattern("file.md", "*.txt"))
end

T["Files utils"]["match_pattern"]["matches wildcard at start"] = function()
  h.eq(true, files.match_pattern("test_file.lua", "*_file.lua"))
  h.eq(true, files.match_pattern("my_test_file.lua", "*_file.lua"))
  h.eq(false, files.match_pattern("test_file.txt", "*_file.lua"))
end

T["Files utils"]["match_pattern"]["matches wildcard in middle"] = function()
  h.eq(true, files.match_pattern("test_spec.lua", "test_*.lua"))
  h.eq(true, files.match_pattern("test_unit.lua", "test_*.lua"))
  h.eq(false, files.match_pattern("test_spec.md", "test_*.lua"))
end

T["Files utils"]["match_pattern"]["matches multiple wildcards"] = function()
  h.eq(true, files.match_pattern("my_test_file.lua", "*_test_*.lua"))
  h.eq(true, files.match_pattern("a_test_b.lua", "*_test_*.lua"))
  h.eq(false, files.match_pattern("my_test_file.md", "*_test_*.lua"))
end

T["Files utils"]["match_pattern"]["matches ? for single character"] = function()
  h.eq(true, files.match_pattern("test1.lua", "test?.lua"))
  h.eq(true, files.match_pattern("testA.lua", "test?.lua"))
  h.eq(false, files.match_pattern("test12.lua", "test?.lua"))
  h.eq(false, files.match_pattern("test.lua", "test?.lua"))
end

T["Files utils"]["match_pattern"]["matches character sets [abc]"] = function()
  h.eq(true, files.match_pattern("test_a.lua", "test_[abc].lua"))
  h.eq(true, files.match_pattern("test_b.lua", "test_[abc].lua"))
  h.eq(true, files.match_pattern("test_c.lua", "test_[abc].lua"))
  h.eq(false, files.match_pattern("test_d.lua", "test_[abc].lua"))
end

T["Files utils"]["match_pattern"]["matches range patterns [0-9]"] = function()
  h.eq(true, files.match_pattern("file1.txt", "file[0-9].txt"))
  h.eq(true, files.match_pattern("file5.txt", "file[0-9].txt"))
  h.eq(false, files.match_pattern("fileA.txt", "file[0-9].txt"))
end

T["Files utils"]["match_pattern"]["escapes special Lua pattern characters"] = function()
  h.eq(true, files.match_pattern("test.file.lua", "test.file.lua"))
  h.eq(true, files.match_pattern("file-name.lua", "file-name.lua"))
  h.eq(true, files.match_pattern("file+name.lua", "file+name.lua"))
  h.eq(true, files.match_pattern("file(1).lua", "file(1).lua"))
end

T["Files utils"]["match_pattern"]["combines glob patterns with special chars"] = function()
  h.eq(true, files.match_pattern("test.spec.lua", "*.spec.lua"))
  h.eq(true, files.match_pattern("my-file.test.md", "*-file.test.md"))
  h.eq(false, files.match_pattern("test.spec.txt", "*.spec.lua"))
end

T["Files utils"]["match_patterns"] = new_set()

T["Files utils"]["match_patterns"]["accepts single pattern as string"] = function()
  h.eq(true, files.match_patterns("test.md", "*.md"))
  h.eq(false, files.match_patterns("test.txt", "*.md"))
end

T["Files utils"]["match_patterns"]["matches against multiple patterns"] = function()
  local patterns = { "*.md", "*.txt", ".clinerules" }
  h.eq(true, files.match_patterns("test.md", patterns))
  h.eq(true, files.match_patterns("file.txt", patterns))
  h.eq(true, files.match_patterns(".clinerules", patterns))
  h.eq(false, files.match_patterns("test.lua", patterns))
end

T["Files utils"]["match_patterns"]["returns true on first match"] = function()
  local patterns = { ".cursorrules", "*.md", "*.txt" }
  h.eq(true, files.match_patterns(".cursorrules", patterns))
end

T["Files utils"]["match_patterns"]["returns false when no patterns match"] = function()
  local patterns = { "*.md", "*.txt" }
  h.eq(false, files.match_patterns("test.lua", patterns))
  h.eq(false, files.match_patterns("script.py", patterns))
end

T["Files utils"]["match_patterns"]["handles empty pattern list"] = function()
  h.eq(false, files.match_patterns("test.md", {}))
end

T["Files utils"]["match_patterns"]["mixes literal and glob patterns"] = function()
  local patterns = { ".clinerules", "*.md", "test_?.lua" }
  h.eq(true, files.match_patterns(".clinerules", patterns))
  h.eq(true, files.match_patterns("README.md", patterns))
  h.eq(true, files.match_patterns("test_1.lua", patterns))
  h.eq(false, files.match_patterns("other.txt", patterns))
end

return T
