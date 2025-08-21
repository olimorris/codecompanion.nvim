local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()
        edit_tracker = require("codecompanion.strategies.chat.edit_tracker")

        -- Helper to create test file content
        function create_test_content()
          return { "line 1", "line 2", "line 3" }
        end

        -- Helper to create modified content
        function create_modified_content()
          return { "line 1 modified", "line 2", "line 3", "line 4 added" }
        end

        -- Helper to create edit info structure
        function create_edit_info(tool_name, filepath, bufnr, original_content, new_content)
          local info = {
            tool_name = tool_name or "test_tool",
            original_content = original_content or create_test_content()
          }

          if filepath then
            info.filepath = filepath
          elseif bufnr then
            info.bufnr = bufnr
          else
            info.bufnr = 1 -- default buffer
          end

          if new_content then
            info.new_content = new_content
          end

          return info
        end

        -- Suppress notifications for clean test output
        local orig_notify = vim.notify
        vim.notify = function() end

        -- Suppress utils.fire calls for clean tests
        local utils = require("codecompanion.utils")
        utils.fire = function() end
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()

        -- Reset any global state
        if chat._tool_monitors then
          chat._tool_monitors = {}
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["init - initializes edit tracker for new chat"] = function()
  child.lua([[
    -- Ensure clean state
    chat.edit_tracker = nil

    edit_tracker.init(chat)

    _G.test_result = {
      tracker_exists = chat.edit_tracker ~= nil,
      has_tracked_files = chat.edit_tracker and chat.edit_tracker.tracked_files ~= nil,
      enabled = chat.edit_tracker and chat.edit_tracker.enabled,
      counter = chat.edit_tracker and chat.edit_tracker.edit_counter
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.tracker_exists)
  h.expect_truthy(result.has_tracked_files)
  h.expect_truthy(result.enabled)
  h.eq(result.counter, 0)
end

T["init - does not reinitialize existing tracker"] = function()
  child.lua([[
    -- Initialize first time
    edit_tracker.init(chat)
    chat.edit_tracker.edit_counter = 5

    -- Try to initialize again
    edit_tracker.init(chat)

    _G.test_result = chat.edit_tracker.edit_counter
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result, 5) -- Should remain unchanged
end

T["register_edit_operation - creates new edit with file path"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = create_edit_info("test_tool", "/test/path.lua", nil,
                                      { "old content" }, { "new content" })

    local edit_id = edit_tracker.register_edit_operation(chat, edit_info)
    local tracked_files = edit_tracker.get_tracked_edits(chat)

    _G.test_result = {
      edit_id_exists = edit_id ~= "",
      tracked_count = vim.tbl_count(tracked_files),
      has_file_key = nil,
      operation_count = 0
    }

    -- Find the tracked file
    for key, file_data in pairs(tracked_files) do
      if key:match("file:") then
        _G.test_result.has_file_key = key
        _G.test_result.operation_count = #file_data.edit_operations
        break
      end
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.edit_id_exists)
  h.eq(result.tracked_count, 1)
  h.expect_truthy(result.has_file_key ~= nil)
  h.eq(result.operation_count, 1)
end

T["register_edit_operation - creates new edit with buffer number"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = create_edit_info("buffer_tool", nil, 42,
                                      { "buffer content" }, { "modified buffer" })

    local edit_id = edit_tracker.register_edit_operation(chat, edit_info)
    local tracked_files = edit_tracker.get_tracked_edits(chat)

    _G.test_result = {
      edit_id_exists = edit_id ~= "",
      has_buffer_key = false
    }

    for key, file_data in pairs(tracked_files) do
      if key == "buffer:42" then
        _G.test_result.has_buffer_key = true
        _G.test_result.operation_data = file_data.edit_operations[1]
        break
      end
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.edit_id_exists)
  h.expect_truthy(result.has_buffer_key)
  h.eq(result.operation_data.tool_name, "buffer_tool")
end

T["register_edit_operation - requires tool_name"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = {
      filepath = "/test/path.lua",
      original_content = { "content" }
    }
    -- Missing tool_name

    local success = pcall(function()
      edit_tracker.register_edit_operation(chat, edit_info)
    end)

    _G.test_result = success
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result, false) -- Should fail due to missing tool_name
end

T["register_edit_operation - requires original_content"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = {
      tool_name = "test_tool",
      filepath = "/test/path.lua"
    }
    -- Missing original_content

    local success = pcall(function()
      edit_tracker.register_edit_operation(chat, edit_info)
    end)

    _G.test_result = success
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result, false) -- Should fail due to missing original_content
end

T["register_edit_operation - detects duplicate edits"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = create_edit_info("duplicate_tool", "/test/same.lua", nil,
                                      { "same content" }, { "same result" })

    local first_id = edit_tracker.register_edit_operation(chat, edit_info)
    local second_id = edit_tracker.register_edit_operation(chat, edit_info)

    local tracked_files = edit_tracker.get_tracked_edits(chat)
    local operation_count = 0

    for _, file_data in pairs(tracked_files) do
      operation_count = operation_count + #file_data.edit_operations
    end

    _G.test_result = {
      first_id = first_id,
      second_id = second_id,
      ids_equal = first_id == second_id,
      operation_count = operation_count
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.ids_equal) -- Should return same ID for duplicate
  h.eq(result.operation_count, 1) -- Should only have one operation
end

T["update_edit_status - updates existing operation"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = create_edit_info("status_tool", "/test/status.lua")
    local edit_id = edit_tracker.register_edit_operation(chat, edit_info)

    local update_success = edit_tracker.update_edit_status(chat, edit_id, "rejected")
    local operation, key = edit_tracker.get_edit_operation(chat, edit_id)

    _G.test_result = {
      update_success = update_success,
      new_status = operation and operation.status,
      operation_found = operation ~= nil
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.update_success)
  h.expect_truthy(result.operation_found)
  h.eq(result.new_status, "rejected")
end

T["update_edit_status - fails for non-existent operation"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local update_success = edit_tracker.update_edit_status(chat, "nonexistent_id", "accepted")

    _G.test_result = update_success
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result, false)
end

T["update_edit_status - updates content when provided"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = create_edit_info("content_tool", "/test/content.lua")
    local edit_id = edit_tracker.register_edit_operation(chat, edit_info)

    local new_content = { "updated line 1", "updated line 2" }
    local update_success = edit_tracker.update_edit_status(chat, edit_id, "accepted", new_content)
    local operation, key = edit_tracker.get_edit_operation(chat, edit_id)

    _G.test_result = {
      update_success = update_success,
      new_content = operation and operation.new_content,
      content_matches = operation and vim.deep_equal(operation.new_content, new_content)
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.update_success)
  h.expect_truthy(result.content_matches)
end

T["get_edit_operation - finds existing operation"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local edit_info = create_edit_info("find_tool", "/test/find.lua")
    local edit_id = edit_tracker.register_edit_operation(chat, edit_info)

    local operation, key = edit_tracker.get_edit_operation(chat, edit_id)

    _G.test_result = {
      operation_found = operation ~= nil,
      key_found = key ~= nil,
      tool_name_matches = operation and operation.tool_name == "find_tool",
      id_matches = operation and operation.id == edit_id
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.operation_found)
  h.expect_truthy(result.key_found)
  h.expect_truthy(result.tool_name_matches)
  h.expect_truthy(result.id_matches)
end

T["get_edit_operation - returns nil for non-existent operation"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local operation, key = edit_tracker.get_edit_operation(chat, "missing_id")

    _G.test_result = {
      operation_is_nil = operation == nil,
      key_is_nil = key == nil
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.operation_is_nil)
  h.expect_truthy(result.key_is_nil)
end

T["get_edit_operations_for_file - returns operations for filepath"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local filepath = "/test/specific.lua"
    local edit_info1 = create_edit_info("tool1", filepath)
    local edit_info2 = create_edit_info("tool2", filepath)

    edit_tracker.register_edit_operation(chat, edit_info1)
    edit_tracker.register_edit_operation(chat, edit_info2)

    local operations = edit_tracker.get_edit_operations_for_file(chat, filepath)

    _G.test_result = {
      operation_count = #operations,
      has_tool1 = false,
      has_tool2 = false
    }

    for _, op in ipairs(operations) do
      if op.tool_name == "tool1" then
        _G.test_result.has_tool1 = true
      elseif op.tool_name == "tool2" then
        _G.test_result.has_tool2 = true
      end
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result.operation_count, 2)
  h.expect_truthy(result.has_tool1)
  h.expect_truthy(result.has_tool2)
end

T["get_edit_operations_for_file - returns operations for buffer"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local bufnr = 100
    local edit_info = create_edit_info("buffer_tool", nil, bufnr)
    edit_tracker.register_edit_operation(chat, edit_info)

    local operations = edit_tracker.get_edit_operations_for_file(chat, bufnr)

    _G.test_result = {
      operation_count = #operations,
      tool_name = operations[1] and operations[1].tool_name
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result.operation_count, 1)
  h.eq(result.tool_name, "buffer_tool")
end

T["get_edit_stats - returns correct statistics"] = function()
  child.lua([[
    edit_tracker.init(chat)

    -- Create operations with different statuses
    local edit1 = create_edit_info("tool1", "/file1.lua")
    local edit2 = create_edit_info("tool2", "/file2.lua")
    local edit3 = create_edit_info("tool1", "/file3.lua")

    local id1 = edit_tracker.register_edit_operation(chat, edit1)
    local id2 = edit_tracker.register_edit_operation(chat, edit2)
    local id3 = edit_tracker.register_edit_operation(chat, edit3)

    -- Update some statuses
    edit_tracker.update_edit_status(chat, id2, "rejected")

    local stats = edit_tracker.get_edit_stats(chat)

    _G.test_result = {
      total_files = stats.total_files,
      total_operations = stats.total_operations,
      accepted_operations = stats.accepted_operations,
      rejected_operations = stats.rejected_operations,
      tools_used = stats.tools_used
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result.total_files, 3)
  h.eq(result.total_operations, 3)
  h.eq(result.accepted_operations, 2)
  h.eq(result.rejected_operations, 1)
  h.expect_tbl_contains("tool1", result.tools_used)
  h.expect_tbl_contains("tool2", result.tools_used)
end

T["get_edit_stats - handles uninitialized tracker"] = function()
  child.lua([[
    -- Don't initialize tracker
    chat.edit_tracker = nil

    local stats = edit_tracker.get_edit_stats(chat)

    _G.test_result = {
      total_files = stats.total_files,
      total_operations = stats.total_operations,
      tools_used_count = #stats.tools_used
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result.total_files, 0)
  h.eq(result.total_operations, 0)
  h.eq(result.tools_used_count, 0)
end

T["_content_equal - detects equal content"] = function()
  child.lua([[
    local content1 = { "line 1", "line 2", "line 3" }
    local content2 = { "line 1", "line 2", "line 3" }

    local result = edit_tracker._content_equal(content1, content2)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result)
end

T["_content_equal - detects different content"] = function()
  child.lua([[
    local content1 = { "line 1", "line 2", "line 3" }
    local content2 = { "line 1", "modified line 2", "line 3" }

    local result = edit_tracker._content_equal(content1, content2)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result, false)
end

T["_content_equal - detects different lengths"] = function()
  child.lua([[
    local content1 = { "line 1", "line 2" }
    local content2 = { "line 1", "line 2", "line 3" }

    local result = edit_tracker._content_equal(content1, content2)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result, false)
end

T["clear - removes all tracked edits"] = function()
  child.lua([[
    edit_tracker.init(chat)

    -- Add some operations
    local edit1 = create_edit_info("tool1", "/file1.lua")
    local edit2 = create_edit_info("tool2", "/file2.lua")
    edit_tracker.register_edit_operation(chat, edit1)
    edit_tracker.register_edit_operation(chat, edit2)

    -- Verify we have data
    local stats_before = edit_tracker.get_edit_stats(chat)

    -- Clear all data
    edit_tracker.clear(chat)

    -- Check after clearing
    local stats_after = edit_tracker.get_edit_stats(chat)

    _G.test_result = {
      files_before = stats_before.total_files,
      operations_before = stats_before.total_operations,
      files_after = stats_after.total_files,
      operations_after = stats_after.total_operations,
      counter_reset = chat.edit_tracker.edit_counter
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.files_before > 0)
  h.expect_truthy(result.operations_before > 0)
  h.eq(result.files_after, 0)
  h.eq(result.operations_after, 0)
  h.eq(result.counter_reset, 0)
end

T["start_tool_monitoring - sets up monitoring state"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local tool_args = { filepath = "test_monitor.lua" }
    edit_tracker.start_tool_monitoring("test_tool", chat, tool_args)

    _G.test_result = {
      monitors_exist = chat._tool_monitors ~= nil,
      tool_monitor_exists = chat._tool_monitors and chat._tool_monitors["test_tool"] ~= nil,
      has_start_time = false,
      is_monitoring = false
    }

    if chat._tool_monitors and chat._tool_monitors["test_tool"] then
      local monitor = chat._tool_monitors["test_tool"]
      _G.test_result.has_start_time = monitor.start_time ~= nil
      _G.test_result.is_monitoring = monitor.monitoring == true
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.monitors_exist)
  h.expect_truthy(result.tool_monitor_exists)
  h.expect_truthy(result.has_start_time)
  h.expect_truthy(result.is_monitoring)
end

T["finish_tool_monitoring - cleans up monitoring state"] = function()
  child.lua([[
    edit_tracker.init(chat)

    -- Start monitoring
    edit_tracker.start_tool_monitoring("cleanup_tool", chat)

    -- Verify monitoring exists
    local monitoring_before = chat._tool_monitors and chat._tool_monitors["cleanup_tool"] ~= nil

    -- Finish monitoring
    local changes_detected = edit_tracker.finish_tool_monitoring("cleanup_tool", chat, true)

    -- Check cleanup
    local monitoring_after = chat._tool_monitors and chat._tool_monitors["cleanup_tool"] ~= nil

    _G.test_result = {
      monitoring_before = monitoring_before,
      monitoring_after = monitoring_after,
      changes_count = changes_detected
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.monitoring_before)
  h.eq(result.monitoring_after, false) -- Should be cleaned up
  h.eq(result.changes_count, 0) -- No actual file changes in test
end

T["finish_tool_monitoring - handles non-existent monitoring"] = function()
  child.lua([[
    edit_tracker.init(chat)

    -- Try to finish monitoring that never started
    local changes_detected = edit_tracker.finish_tool_monitoring("nonexistent_tool", chat, true)

    _G.test_result = changes_detected
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(result, 0)
end

T["disabled tracking - skips registration when disabled"] = function()
  child.lua([[
    edit_tracker.init(chat)
    chat.edit_tracker.enabled = false

    local edit_info = create_edit_info("disabled_tool", "/test/disabled.lua")
    local edit_id = edit_tracker.register_edit_operation(chat, edit_info)

    local stats = edit_tracker.get_edit_stats(chat)

    _G.test_result = {
      edit_id_empty = edit_id == "",
      no_operations = stats.total_operations == 0
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.edit_id_empty)
  h.expect_truthy(result.no_operations)
end

T["integration - complete edit workflow"] = function()
  child.lua([[
    edit_tracker.init(chat)

    local workflow_success = true

    -- Step 1: Register multiple edits
    local file1_edit = create_edit_info("create_tool", "/project/new_file.lua", nil, {}, {"-- New file"})
    local file2_edit = create_edit_info("edit_tool", "/project/existing.lua", nil, {"old"}, {"new"})
    local buffer_edit = create_edit_info("buffer_tool", nil, 50, {"buffer old"}, {"buffer new"})

    local id1 = edit_tracker.register_edit_operation(chat, file1_edit)
    local id2 = edit_tracker.register_edit_operation(chat, file2_edit)
    local id3 = edit_tracker.register_edit_operation(chat, buffer_edit)

    workflow_success = workflow_success and (id1 ~= "") and (id2 ~= "") and (id3 ~= "")

    -- Step 2: Update some statuses
    workflow_success = workflow_success and edit_tracker.update_edit_status(chat, id2, "rejected")

    -- Step 3: Retrieve operations
    local op1, key1 = edit_tracker.get_edit_operation(chat, id1)
    local file2_ops = edit_tracker.get_edit_operations_for_file(chat, "/project/existing.lua")
    local buffer_ops = edit_tracker.get_edit_operations_for_file(chat, 50)

    workflow_success = workflow_success and (op1 ~= nil) and (#file2_ops == 1) and (#buffer_ops == 1)

    -- Step 4: Check statistics
    local stats = edit_tracker.get_edit_stats(chat)
    workflow_success = workflow_success and (stats.total_files == 3) and
                      (stats.total_operations == 3) and (stats.rejected_operations == 1)

    -- Step 5: Test tool monitoring
    edit_tracker.start_tool_monitoring("integration_tool", chat)
    local changes = edit_tracker.finish_tool_monitoring("integration_tool", chat, true)
    workflow_success = workflow_success and (changes == 0) -- No actual file changes

    _G.test_result = workflow_success
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result)
end

return T
