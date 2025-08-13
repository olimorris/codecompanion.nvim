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
        super_diff = require("codecompanion.helpers.super_diff")
        edit_tracker = require("codecompanion.strategies.chat.edit_tracker")

        -- Mock config to include debug_and_super_diff_window
        local config = require("codecompanion.config")
        if not config.display then
          config.display = {}
        end
        if not config.display.chat then
          config.display.chat = {}
        end
        config.display.chat.debug_and_super_diff_window = {
          width = 80,
          height = 20,
          row = "center",
          col = "center",
          relative = "editor",
          opts = {
            wrap = true,
            number = true,
            relativenumber = false,
          },
        }

        -- Initialize edit tracker for the chat
        edit_tracker.init(chat)

        -- Helper to create mock tracked files with edit operations
        function create_test_tracked_files()
          return {
            ["file:test.lua"] = {
              filepath = "test.lua",
              bufnr = 1,
              type = "file",
              edit_operations = {
                {
                  id = "op1",
                  tool_name = "edit_file",
                  status = "accepted",
                  timestamp = 1000000000000000000,
                  original_content = { "local x = 1", "print(x)" },
                  new_content = { "local x = 2", "print(x)" },
                  metadata = { explanation = "Updated variable value" }
                }
              }
            },
            ["file:example.py"] = {
              filepath = "example.py",
              bufnr = 2,
              type = "file",
              edit_operations = {
                {
                  id = "op2",
                  tool_name = "create_file",
                  status = "pending",
                  timestamp = 2000000000000000000,
                  original_content = {},
                  new_content = { "def hello():", "    print('world')" },
                  metadata = { explanation = "Created new function" }
                }
              }
            }
          }
        end

        -- Helper to add mock data to chat's edit tracker
        function setup_mock_data()
          chat.edit_tracker.tracked_files = create_test_tracked_files()
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
        -- Clean up any buffers created during tests
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
          end
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["show_super_diff - handles empty tracked files"] = function()
  child.lua([[
    -- Mock vim.notify to capture notifications
    local notification_received = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg and msg:find("No edits to show") then
        notification_received = true
      end
    end

    super_diff.show_super_diff(chat)

    vim.notify = orig_notify
    _G.test_result = notification_received
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result)
end

T["show_super_diff - creates buffer with tracked files"] = function()
  child.lua([[
    setup_mock_data()

    local initial_buffers = #vim.api.nvim_list_bufs()

    -- Suppress notifications for clean test
    local orig_notify = vim.notify
    vim.notify = function() end

    local success = pcall(function()
      super_diff.show_super_diff(chat)
    end)

    vim.notify = orig_notify

    local final_buffers = #vim.api.nvim_list_bufs()
    _G.test_result = success and (final_buffers > initial_buffers)
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result)
end

T["show_super_diff - creates markdown buffer"] = function()
  child.lua([[
    setup_mock_data()

    local orig_notify = vim.notify
    vim.notify = function() end

    local success = pcall(function()
      super_diff.show_super_diff(chat)
    end)

    vim.notify = orig_notify

    -- Find the markdown buffer
    local markdown_buf = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
        markdown_buf = buf
        break
      end
    end

    _G.test_result = {
      success = success,
      buffer_found = markdown_buf ~= nil,
      has_content = false,
      has_file_headers = false
    }

    if markdown_buf then
      local lines = vim.api.nvim_buf_get_lines(markdown_buf, 0, -1, false)
      _G.test_result.has_content = #lines > 0

      for _, line in ipairs(lines) do
        if line:match("^## ") then
          _G.test_result.has_file_headers = true
          break
        end
      end
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.success)
  h.expect_truthy(result.buffer_found)
  h.expect_truthy(result.has_content)
  h.expect_truthy(result.has_file_headers)
end

T["setup_keymaps - creates buffer keymaps"] = function()
  child.lua([[
    local buf = vim.api.nvim_create_buf(false, true)
    local ns_id = vim.api.nvim_create_namespace("test_super_diff")
    local file_sections = {}

    super_diff.setup_keymaps(buf, chat, file_sections, ns_id)

    local keymaps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local keymap_lhs = {}
    for _, keymap in ipairs(keymaps) do
      table.insert(keymap_lhs, keymap.lhs)
    end

    vim.api.nvim_buf_delete(buf, { force = true })

    _G.test_result = keymap_lhs
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_tbl_contains("ga", result) -- Accept all
  h.expect_tbl_contains("gr", result) -- Reject all
  h.expect_tbl_contains("q", result) -- Close
end

T["setup_sticky_header - creates autocmds"] = function()
  child.lua([[
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {
      "## test.lua",
      "Some content",
      "More content"
    }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.api.nvim_set_current_buf(buf)
    local win = vim.api.nvim_get_current_win()

    super_diff.setup_sticky_header(buf, win, lines)

    -- Check if autocmds were created
    local augroups = vim.api.nvim_get_autocmds({})
    local found_sticky_autocmd = false

    for _, autocmd in ipairs(augroups) do
      if autocmd.group_name and autocmd.group_name:match("codecompanion_super_diff_sticky_") then
        found_sticky_autocmd = true
        break
      end
    end

    vim.api.nvim_buf_delete(buf, { force = true })

    _G.test_result = found_sticky_autocmd
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result)
end

T["buffer contains expected content structure"] = function()
  child.lua([[
    setup_mock_data()

    local orig_notify = vim.notify
    vim.notify = function() end

    local success = pcall(function()
      super_diff.show_super_diff(chat)
    end)

    vim.notify = orig_notify

    -- Find and analyze the markdown buffer
    local markdown_buf = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
        markdown_buf = buf
        break
      end
    end

    _G.test_result = {
      success = success,
      has_operations_section = false,
      has_code_blocks = false,
      has_status_indicators = false,
      line_count = 0
    }

    if markdown_buf then
      local lines = vim.api.nvim_buf_get_lines(markdown_buf, 0, -1, false)
      _G.test_result.line_count = #lines

      for _, line in ipairs(lines) do
        if line:match("Operations:") then
          _G.test_result.has_operations_section = true
        end
        if line:match("^```") then
          _G.test_result.has_code_blocks = true
        end
        if line:match("✔️") or line:match("❌") or line:match("ACCEPTED") or line:match("PENDING") then
          _G.test_result.has_status_indicators = true
        end
      end
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.success)
  h.expect_truthy(result.line_count > 0)
  h.expect_truthy(result.has_operations_section)
  h.expect_truthy(result.has_status_indicators)
end

T["handles mixed operation statuses"] = function()
  child.lua([[
    -- Create tracked files with mixed statuses
    chat.edit_tracker.tracked_files = {
      ["file:mixed.lua"] = {
        filepath = "mixed.lua",
        bufnr = 1,
        type = "file",
        edit_operations = {
          {
            id = "accepted_op",
            tool_name = "edit_file",
            status = "accepted",
            timestamp = 1000000000000000000,
            original_content = { "print('old')" },
            new_content = { "print('new')" },
            metadata = { explanation = "Updated message" }
          },
          {
            id = "pending_op",
            tool_name = "edit_file",
            status = "pending",
            timestamp = 2000000000000000000,
            original_content = { "print('new')" },
            new_content = { "print('newer')" },
            metadata = { explanation = "Another update" }
          },
          {
            id = "rejected_op",
            tool_name = "edit_file",
            status = "rejected",
            timestamp = 3000000000000000000,
            original_content = { "print('newer')" },
            new_content = { "print('newest')" },
            metadata = { explanation = "Final update" }
          }
        }
      }
    }

    local orig_notify = vim.notify
    vim.notify = function() end

    local success = pcall(function()
      super_diff.show_super_diff(chat)
    end)

    vim.notify = orig_notify

    -- Find markdown buffer and check for mixed status indicators
    local markdown_buf = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
        markdown_buf = buf
        break
      end
    end

    _G.test_result = {
      success = success,
      has_accepted = false,
      has_pending = false,
      has_rejected = false
    }

    if markdown_buf then
      local lines = vim.api.nvim_buf_get_lines(markdown_buf, 0, -1, false)

      for _, line in ipairs(lines) do
        if line:match("ACCEPTED") or line:match("✔️.*ACCEPTED") then
          _G.test_result.has_accepted = true
        end
        if line:match("PENDING") or line:match("pending") then
          _G.test_result.has_pending = true
        end
        if line:match("REJECTED") or line:match("❌.*REJECTED") then
          _G.test_result.has_rejected = true
        end
      end
    end
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.success)
  h.expect_truthy(result.has_accepted)
  h.expect_truthy(result.has_rejected)
end

T["integration - complete workflow"] = function()
  child.lua([[
    -- Setup comprehensive mock data
    chat.edit_tracker.tracked_files = {
      ["file:workflow.lua"] = {
        filepath = "workflow.lua",
        bufnr = 1,
        type = "file",
        edit_operations = {
          {
            id = "workflow_op",
            tool_name = "edit_file",
            status = "accepted",
            timestamp = 1000000000000000000,
            original_content = { "local x = 1" },
            new_content = { "local x = 2" },
            metadata = { explanation = "Updated variable" }
          }
        }
      }
    }

    local orig_notify = vim.notify
    vim.notify = function() end

    local workflow_success = true

    -- Test 1: Show super diff
    local ok = pcall(function()
      super_diff.show_super_diff(chat)
    end)
    workflow_success = workflow_success and ok

    -- Test 2: Find the created buffer
    local super_diff_buf = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
        super_diff_buf = buf
        break
      end
    end

    workflow_success = workflow_success and (super_diff_buf ~= nil)

    if super_diff_buf then
      -- Test 3: Check buffer content
      local lines = vim.api.nvim_buf_get_lines(super_diff_buf, 0, -1, false)
      workflow_success = workflow_success and (#lines > 0)

      -- Test 4: Setup keymaps
      local ns_id = vim.api.nvim_create_namespace("test_integration")
      local ok_keymaps = pcall(function()
        super_diff.setup_keymaps(super_diff_buf, chat, {}, ns_id)
      end)
      workflow_success = workflow_success and ok_keymaps

      -- Test 5: Check keymaps exist
      local keymaps = vim.api.nvim_buf_get_keymap(super_diff_buf, 'n')
      workflow_success = workflow_success and (#keymaps > 0)
    end

    vim.notify = orig_notify
    _G.test_result = workflow_success
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result)
end

T["reject then accept workflow - operations can be reapplied"] = function()
  child.lua([[
    -- First create the edit operation through the normal flow
    edit_tracker.init(chat)
    local edit_info = {
      tool_name = "test_tool",
      filepath = "/test/reapply.lua",
      original_content = { "local x = 1" },
      new_content = { "local x = 2" },
      status = "accepted" -- This will be normalized to accepted
    }

    local edit_id = edit_tracker.register_edit_operation(chat, edit_info)

    -- Now manually set it to rejected to simulate the reject workflow
    edit_tracker.update_edit_status(chat, edit_id, "rejected")

    local orig_notify = vim.notify
    vim.notify = function() end

    -- Check initial state (should have 1 rejected operation)
    local stats_initial = edit_tracker.get_edit_stats(chat)

    -- Now simulate the accept all workflow - should accept rejected operations
    for _, tracked_file in pairs(edit_tracker.get_tracked_edits(chat)) do
      for _, operation in ipairs(tracked_file.edit_operations) do
        if operation.status == "rejected" then
          edit_tracker.update_edit_status(chat, operation.id, "accepted")
        end
      end
    end

    local stats_final = edit_tracker.get_edit_stats(chat)

    vim.notify = orig_notify

    _G.test_result = {
      initial_rejected = stats_initial.rejected_operations,
      initial_accepted = stats_initial.accepted_operations,
      final_accepted = stats_final.accepted_operations,
      final_rejected = stats_final.rejected_operations,
      workflow_success = (stats_initial.rejected_operations == 1) and
                        (stats_initial.accepted_operations == 0) and
                        (stats_final.accepted_operations == 1) and
                        (stats_final.rejected_operations == 0)
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.expect_truthy(result.workflow_success)
end

return T
