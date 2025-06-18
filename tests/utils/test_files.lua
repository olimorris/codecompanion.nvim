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

return T
