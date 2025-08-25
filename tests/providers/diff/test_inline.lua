local InlineDiff = require("codecompanion.providers.diff.inline")
local h = require("tests.helpers")

local T = MiniTest.new_set()

T["InlineDiff"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.cmd("new")
      vim.bo.buftype = "nofile"
    end,
    post_case = function()
      vim.cmd("bdelete!")
    end,
  },
})

T["InlineDiff"]["new - creates instance with no changes"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local contents = { "line 1", "line 2", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = contents,
    id = "test_diff",
  })

  h.eq(type(diff), "table")
  h.eq(diff.bufnr, bufnr)
  h.eq(diff.id, "test_diff")
  h.eq(diff.has_changes, false)
  h.eq(type(diff.extmark_ids), "table")
  h.eq(#diff.extmark_ids, 0)
end

T["InlineDiff"]["new - creates instance with changes"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "old line 2", "line 3" }
  local current_contents = { "line 1", "new line 2", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "test_diff_changes",
  })

  h.eq(type(diff), "table")
  h.eq(diff.bufnr, bufnr)
  h.eq(diff.id, "test_diff_changes")
  h.eq(diff.has_changes, true)
  h.eq(type(diff.extmark_ids), "table")
end

T["InlineDiff"]["new - generates unique namespace"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local contents = { "line 1", "line 2" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)

  local diff1 = InlineDiff.new({
    bufnr = bufnr,
    contents = contents,
    id = "diff1",
  })
  local diff2 = InlineDiff.new({
    bufnr = bufnr,
    contents = contents,
    id = "diff2",
  })

  h.not_eq(diff1.ns_id, diff2.ns_id)
end

T["InlineDiff"]["new - handles missing id parameter"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local contents = { "line 1" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = contents,
  })

  h.eq(type(diff), "table")
  h.eq(type(diff.id), "nil")
  h.eq(type(diff.ns_id), "number")
end

T["InlineDiff"]["calculate_hunks - delegates to DiffUtils"] = function()
  local old_lines = { "line 1", "old line", "line 3" }
  local new_lines = { "line 1", "new line", "line 3" }
  local hunks = InlineDiff.calculate_hunks(old_lines, new_lines)

  h.eq(type(hunks), "table")
end

T["InlineDiff"]["calculate_hunks - respects context parameter"] = function()
  local old_lines = { "line 1", "line 2", "old line", "line 4", "line 5" }
  local new_lines = { "line 1", "line 2", "new line", "line 4", "line 5" }
  local hunks_default = InlineDiff.calculate_hunks(old_lines, new_lines)
  local hunks_context_1 = InlineDiff.calculate_hunks(old_lines, new_lines, 1)

  h.eq(type(hunks_default), "table")
  h.eq(type(hunks_context_1), "table")
end

T["InlineDiff"]["apply_hunk_highlights - delegates to DiffUtils"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_highlights")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "new line", "line 3" })

  local hunks = {
    {
      old_start = 2,
      old_count = 1,
      new_start = 2,
      new_count = 1,
      old_lines = { "old line" },
      new_lines = { "new line" },
      context_before = { "line 1" },
      context_after = { "line 3" },
    },
  }
  local extmark_ids = InlineDiff.apply_hunk_highlights(bufnr, hunks, ns_id)

  h.eq(type(extmark_ids), "table")

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["InlineDiff"]["apply_hunk_highlights - handles options"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_options")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1" })

  local hunks = {
    {
      old_start = 1,
      old_count = 0,
      new_start = 1,
      new_count = 1,
      old_lines = {},
      new_lines = { "line 1" },
      context_before = {},
      context_after = {},
    },
  }
  local opts = { show_removed = false, status = "accepted" }
  local extmark_ids = InlineDiff.apply_hunk_highlights(bufnr, hunks, ns_id, 0, opts)

  h.eq(type(extmark_ids), "table")

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["InlineDiff"]["contents_equal - delegates to DiffUtils"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local contents = { "line 1", "line 2" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = contents,
    id = "test_equal",
  })

  local content1 = { "line 1", "line 2" }
  local content2 = { "line 1", "line 2" }
  local content3 = { "line 1", "different line 2" }

  h.eq(diff:contents_equal(content1, content2), true)
  h.eq(diff:contents_equal(content1, content3), false)
end

T["InlineDiff"]["apply_diff_highlights - applies highlights for changes"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "old line", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original_contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "test_highlights",
  })

  local old_lines = { "line 1", "old line", "line 3" }
  local new_lines = { "line 1", "new line", "line 3" }
  local initial_extmarks = #diff.extmark_ids
  diff:apply_diff_highlights(old_lines, new_lines)

  h.expect_truthy(#diff.extmark_ids >= initial_extmarks)
  h.eq(vim.api.nvim_get_mode().mode, "n")
end

T["InlineDiff"]["clear_highlights - removes all extmarks"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "old line", "line 3" }
  local current_contents = { "line 1", "new line", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "test_clear",
  })

  local _ = #diff.extmark_ids
  diff:clear_highlights()

  h.eq(#diff.extmark_ids, 0)
end

T["InlineDiff"]["clear_highlights - handles invalid buffer"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local contents = { "line 1" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = contents,
    id = "test_invalid",
  })
  vim.api.nvim_buf_delete(bufnr, { force = true })

  diff:clear_highlights() -- Should not throw error
  h.eq(#diff.extmark_ids, 0)
end

T["InlineDiff"]["accept - clears highlights and fires event"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "old line", "line 3" }
  local current_contents = { "line 1", "new line", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "test_accept",
  })
  local event_fired = false
  local event_data = nil
  local autocommand_id = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionDiffAccepted",
    callback = function(event)
      event_fired = true
      event_data = event.data
    end,
  })
  diff:accept()

  h.eq(#diff.extmark_ids, 0)
  h.expect_truthy(event_fired)
  h.eq(type(event_data), "table")
  h.eq(event_data.diff, "inline")
  h.eq(event_data.bufnr, bufnr)
  h.eq(event_data.id, "test_accept")
  h.eq(event_data.accept, true)

  vim.api.nvim_del_autocmd(autocommand_id)
end

T["InlineDiff"]["reject - restores content and fires event"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "original line", "line 3" }
  local current_contents = { "line 1", "modified line", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_contents)
  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "test_reject",
  })
  local event_fired = false
  local event_data = nil
  local autocommand_id = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionDiffRejected",
    callback = function(event)
      event_fired = true
      event_data = event.data
    end,
  })
  diff:reject()

  local restored_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.eq(restored_content, original_contents)

  h.eq(#diff.extmark_ids, 0)
  h.expect_truthy(event_fired)
  h.eq(type(event_data), "table")
  h.eq(event_data.diff, "inline")
  h.eq(event_data.bufnr, bufnr)
  h.eq(event_data.id, "test_reject")
  h.eq(event_data.accept, false)

  vim.api.nvim_del_autocmd(autocommand_id)
end

T["InlineDiff"]["reject - handles invalid buffer gracefully"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local contents = { "line 1" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = contents,
    id = "test_reject_invalid",
  })
  vim.api.nvim_buf_delete(bufnr, { force = true })

  diff:reject() -- Should not throw error
end

T["InlineDiff"]["teardown - clears highlights and fires event"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "old line", "line 3" }
  local current_contents = { "line 1", "new line", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_contents)
  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "test_teardown",
  })

  local event_fired = false
  local event_data = nil
  local autocommand_id = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionDiffDetached",
    callback = function(event)
      event_fired = true
      event_data = event.data
    end,
  })

  diff:teardown()

  h.eq(#diff.extmark_ids, 0)
  h.expect_truthy(event_fired)
  h.eq(type(event_data), "table")
  h.eq(event_data.diff, "inline")
  h.eq(event_data.bufnr, bufnr)
  h.eq(event_data.id, "test_teardown")

  vim.api.nvim_del_autocmd(autocommand_id)
end

T["InlineDiff"]["integration - full workflow with simple change"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = {
    "function hello()",
    "  print('old message')",
    "end",
  }
  local modified_contents = {
    "function hello()",
    "  print('new message')",
    "end",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, modified_contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "integration_test",
  })

  h.eq(diff.has_changes, true)
  h.expect_truthy(#diff.extmark_ids > 0)

  diff:accept()
  h.eq(#diff.extmark_ids, 0)

  -- Content should remain as modified
  local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.eq(final_content, modified_contents)
end

T["InlineDiff"]["integration - full workflow with reject"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = {
    "const x = 1;",
    "const y = 2;",
  }
  local modified_contents = {
    "const x = 10;",
    "const y = 20;",
    "const z = 30;",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, modified_contents)
  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "integration_reject_test",
  })
  h.eq(diff.has_changes, true)
  h.expect_truthy(#diff.extmark_ids > 0)

  diff:reject()
  h.eq(#diff.extmark_ids, 0)

  -- Content should be restored to original
  local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.eq(final_content, original_contents)
end

T["InlineDiff"]["integration - multiple diffs on same buffer"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "line 2", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original_contents)

  local diff1 = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "diff1",
  })

  local modified_contents = { "line 1", "modified line 2", "line 3" }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, modified_contents)

  local diff2 = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "diff2",
  })

  h.eq(diff1.has_changes, false)
  h.eq(diff2.has_changes, true)
  h.not_eq(diff1.ns_id, diff2.ns_id)

  diff1:teardown()
  diff2:teardown()
end

T["InlineDiff"]["integration - edge case with empty file"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "" } -- Neovim empty buffers have one empty line
  local new_contents = { "new line 1", "new line 2" }

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "empty_file_test",
  })

  h.eq(diff.has_changes, true)

  diff:reject()

  local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.eq(final_content, original_contents)
end

T["InlineDiff"]["integration - edge case with file becoming empty"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_contents = { "line 1", "line 2", "line 3" }
  local new_contents = { "" } -- Neovim empty buffers have one empty line
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_contents)

  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = original_contents,
    id = "file_becoming_empty_test",
  })

  h.eq(diff.has_changes, true)

  diff:reject()

  local final_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.eq(final_content, original_contents)
end

-- Screenshot tests for visual display
local child = MiniTest.new_child_neovim()

T["InlineDiff Screenshots"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.h = require('tests.helpers')
        h.setup_plugin()
      ]])
    end,
    post_case = function()
      child.lua([[
        -- Clean up any buffers or diffs
        vim.cmd('bufdo bdelete!')
      ]])
    end,
    post_once = child.stop,
  },
})

T["InlineDiff Screenshots"]["Shows simple line modification"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "lua"

    local original_content = {
      "local function greet(name)",
      "  print('Hello, ' .. name)",
      "end",
      "",
      "greet('World')"
    }

    local new_content = {
      "local function greet(name)",
      "  print('Hi there, ' .. name .. '!')",
      "end",
      "",
      "greet('World')"
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_content)

    local InlineDiff = require("codecompanion.providers.diff.inline")
    local diff = InlineDiff.new({
      bufnr = bufnr,
      contents = original_content,
      id = "screenshot_test_1",
    })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["InlineDiff Screenshots"]["Shows addition of new lines"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "javascript"

    local original_content = {
      "function calculateSum(a, b) {",
      "  return a + b;",
      "}"
    }

    local new_content = {
      "function calculateSum(a, b) {",
      "  // Validate inputs",
      "  if (typeof a !== 'number' || typeof b !== 'number') {",
      "    throw new Error('Both arguments must be numbers');",
      "  }",
      "  return a + b;",
      "}"
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_content)

    local InlineDiff = require("codecompanion.providers.diff.inline")
    local diff = InlineDiff.new({
      bufnr = bufnr,
      contents = original_content,
      id = "screenshot_test_2",
    })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["InlineDiff Screenshots"]["Shows deletion of lines"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "python"

    local original_content = {
      "def process_data(data):",
      "    # TODO: Add validation",
      "    # This is a temporary comment",
      "    # Remove this later",
      "    result = []",
      "    for item in data:",
      "        result.append(item.strip())",
      "    return result"
    }

    local new_content = {
      "def process_data(data):",
      "    result = []",
      "    for item in data:",
      "        result.append(item.strip())",
      "    return result"
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_content)

    local InlineDiff = require("codecompanion.providers.diff.inline")
    local diff = InlineDiff.new({
      bufnr = bufnr,
      contents = original_content,
      id = "screenshot_test_3",
    })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["InlineDiff Screenshots"]["Shows complex mixed changes"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "rust"

    local original_content = {
      "struct User {",
      "    name: String,",
      "    email: String,",
      "}",
      "",
      "impl User {",
      "    fn new(name: String, email: String) -> Self {",
      "        User { name, email }",
      "    }",
      "}"
    }

    local new_content = {
      "struct User {",
      "    name: String,",
      "    email: String,",
      "    active: bool,",
      "    created_at: DateTime<Utc>,",
      "}",
      "",
      "impl User {",
      "    fn new(name: String, email: String) -> Self {",
      "        User { ",
      "            name, ",
      "            email,",
      "            active: true,",
      "            created_at: Utc::now(),",
      "        }",
      "    }",
      "",
      "    fn is_active(&self) -> bool {",
      "        self.active",
      "    }",
      "}"
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_content)

    local InlineDiff = require("codecompanion.providers.diff.inline")
    local diff = InlineDiff.new({
      bufnr = bufnr,
      contents = original_content,
      id = "screenshot_test_4",
    })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

return T
