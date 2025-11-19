local diff_utils = require("codecompanion.providers.diff.utils")
local h = require("tests.helpers")

local T = MiniTest.new_set()

T["DiffUtils"] = MiniTest.new_set({
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

T["DiffUtils"]["calculate_hunks - detects simple addition"] = function()
  local removed_lines = { "line 1", "line 2" }
  local added_lines = { "line 1", "line 2", "line 3" }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)

  h.eq(type(hunks), "table")
  h.expect_truthy(#hunks > 0)
end

T["DiffUtils"]["calculate_hunks - detects simple deletion"] = function()
  local removed_lines = { "line 1", "line 2", "line 3" }
  local added_lines = { "line 1", "line 3" }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)

  h.eq(type(hunks), "table")
  h.expect_truthy(#hunks > 0)
end

T["DiffUtils"]["calculate_hunks - detects modification"] = function()
  local removed_lines = { "line 1", "old line 2", "line 3" }
  local added_lines = { "line 1", "new line 2", "line 3" }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)

  h.eq(type(hunks), "table")
  h.expect_truthy(#hunks > 0)
end

T["DiffUtils"]["calculate_hunks - returns empty for identical content"] = function()
  local removed_lines = { "line 1", "line 2", "line 3" }
  local added_lines = { "line 1", "line 2", "line 3" }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)

  h.eq(type(hunks), "table")
  h.eq(#hunks, 0)
end

T["DiffUtils"]["calculate_hunks - handles empty content"] = function()
  local removed_lines = {}
  local added_lines = { "new line" }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)

  h.eq(type(hunks), "table")
end

T["DiffUtils"]["calculate_hunks - respects context lines parameter"] = function()
  local removed_lines = { "line 1", "line 2", "line 3", "line 4", "line 5" }
  local added_lines = { "line 1", "modified line 2", "line 3", "line 4", "line 5" }

  local hunks_default = diff_utils.calculate_hunks(removed_lines, added_lines)
  local hunks_context_1 = diff_utils.calculate_hunks(removed_lines, added_lines, 1)

  h.eq(type(hunks_default), "table")
  h.eq(type(hunks_context_1), "table")
end

T["DiffUtils"]["calculate_hunks - returns valid hunk structure"] = function()
  local removed_lines = { "line 1", "old line", "line 3" }
  local added_lines = { "line 1", "new line", "line 3" }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)

  if #hunks > 0 then
    local hunk = hunks[1]
    h.eq(type(hunk.original_start), "number")
    h.eq(type(hunk.original_count), "number")
    h.eq(type(hunk.updated_start), "number")
    h.eq(type(hunk.updated_count), "number")
    h.eq(type(hunk.removed_lines), "table")
    h.eq(type(hunk.added_lines), "table")
    h.eq(type(hunk.context_before), "table")
    h.eq(type(hunk.context_after), "table")
  end
end

T["DiffUtils"]["apply_hunk_highlights - returns extmark ids"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_diff")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "new line", "line 3" })
  local hunks = {
    {
      original_start = 2,
      original_count = 1,
      updated_start = 2,
      updated_count = 1,
      removed_lines = { "old line" },
      added_lines = { "new line" },
      context_before = { "line 1" },
      context_after = { "line 3" },
    },
  }

  local extmark_ids = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id)
  h.eq(type(extmark_ids), "table")

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["DiffUtils"]["apply_hunk_highlights - handles empty hunks"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_diff")
  local extmark_ids = diff_utils.apply_hunk_highlights(bufnr, {}, ns_id)

  h.eq(type(extmark_ids), "table")
  h.eq(#extmark_ids, 0)
end

T["DiffUtils"]["apply_hunk_highlights - respects line offset"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_diff")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "header", "line 1", "new line", "line 3" })
  local hunks = {
    {
      original_start = 2,
      original_count = 1,
      updated_start = 2,
      updated_count = 1,
      removed_lines = { "old line" },
      added_lines = { "new line" },
      context_before = { "line 1" },
      context_after = { "line 3" },
    },
  }
  local extmark_ids = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 1)

  h.eq(type(extmark_ids), "table")

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["DiffUtils"]["apply_hunk_highlights - handles different status"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_diff")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "new line", "line 3" })
  local hunks = {
    {
      original_start = 2,
      original_count = 1,
      updated_start = 2,
      updated_count = 1,
      removed_lines = { "old line" },
      added_lines = { "new line" },
      context_before = { "line 1" },
      context_after = { "line 3" },
    },
  }

  local extmark_ids_pending = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "pending" })
  local extmark_ids_accepted = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "accepted" })
  local extmark_ids_rejected = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "rejected" })

  h.eq(type(extmark_ids_pending), "table")
  h.eq(type(extmark_ids_accepted), "table")
  h.eq(type(extmark_ids_rejected), "table")

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["DiffUtils"]["get_sign_highlight_for_change - returns highlight for added lines"] = function()
  local highlight = diff_utils.get_sign_highlight_for_change("added", false)

  h.eq(type(highlight), "string")
end

T["DiffUtils"]["get_sign_highlight_for_change - returns highlight for removed lines"] = function()
  local highlight = diff_utils.get_sign_highlight_for_change("removed", false)

  h.eq(type(highlight), "string")
end

T["DiffUtils"]["get_sign_highlight_for_change - returns highlight for modifications"] = function()
  local highlight = diff_utils.get_sign_highlight_for_change("added", true)

  h.eq(type(highlight), "string")
end

T["DiffUtils"]["get_sign_highlight_for_change - handles rejected status"] = function()
  local highlight_groups = {
    addition = "DiagnosticError",
    deletion = "DiagnosticError",
    modification = "DiagnosticError",
  }
  local highlight = diff_utils.get_sign_highlight_for_change("added", false, highlight_groups)

  h.eq(highlight, "DiagnosticError")
end

T["DiffUtils"]["get_sign_highlight_for_change - defaults to pending status"] = function()
  local highlight_default = diff_utils.get_sign_highlight_for_change("added", false)
  local highlight_groups = {
    addition = "DiagnosticOk",
    deletion = "DiagnosticError",
    modification = "DiagnosticWarn",
  }
  local highlight_explicit = diff_utils.get_sign_highlight_for_change("added", false, highlight_groups)

  h.eq(highlight_default, "DiagnosticOk")
  h.eq(highlight_explicit, "DiagnosticOk")
end

-- Test are_contents_equal function
T["DiffUtils"]["are_contents_equal - returns true for identical content"] = function()
  local content1 = { "line 1", "line 2", "line 3" }
  local content2 = { "line 1", "line 2", "line 3" }
  local result = diff_utils.are_contents_equal(content1, content2)

  h.eq(result, true)
end

T["DiffUtils"]["are_contents_equal - returns false for different content"] = function()
  local content1 = { "line 1", "line 2", "line 3" }
  local content2 = { "line 1", "modified line 2", "line 3" }
  local result = diff_utils.are_contents_equal(content1, content2)

  h.eq(result, false)
end

T["DiffUtils"]["are_contents_equal - returns false for different lengths"] = function()
  local content1 = { "line 1", "line 2" }
  local content2 = { "line 1", "line 2", "line 3" }
  local result = diff_utils.are_contents_equal(content1, content2)

  h.eq(result, false)
end

T["DiffUtils"]["are_contents_equal - handles empty arrays"] = function()
  local content1 = {}
  local content2 = {}
  local result = diff_utils.are_contents_equal(content1, content2)

  h.eq(result, true)
end

T["DiffUtils"]["are_contents_equal - handles one empty array"] = function()
  local content1 = {}
  local content2 = { "line 1" }
  local result = diff_utils.are_contents_equal(content1, content2)

  h.eq(result, false)
end

-- Integration tests
T["DiffUtils"]["integration - full diff workflow"] = function()
  local removed_lines = {
    "function hello()",
    "  print('old')",
    "end",
  }
  local added_lines = {
    "function hello()",
    "  print('new')",
    "  print('extra line')",
    "end",
  }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)
  h.expect_truthy(#hunks > 0)

  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_integration")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, added_lines)

  local extmark_ids = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id)
  h.eq(type(extmark_ids), "table")

  h.eq(diff_utils.are_contents_equal(removed_lines, added_lines), false)
  h.eq(diff_utils.are_contents_equal(removed_lines, removed_lines), true)

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["DiffUtils"]["integration - complex multi-hunk diff"] = function()
  local removed_lines = {
    "line 1",
    "line 2 old",
    "line 3",
    "line 4",
    "line 5 old",
    "line 6",
  }
  local added_lines = {
    "line 1",
    "line 2 new",
    "line 3",
    "inserted line",
    "line 4",
    "line 5 new",
    "line 6",
  }

  local hunks = diff_utils.calculate_hunks(removed_lines, added_lines)
  h.expect_truthy(#hunks > 0)
end

-- Screenshot tests for visual display
local child = MiniTest.new_child_neovim()

T["DiffUtils Screenshots"] = MiniTest.new_set({
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
        -- Clean up any buffers
        vim.cmd('bufdo bdelete!')
      ]])
    end,
    post_once = child.stop,
  },
})

T["DiffUtils Screenshots"]["Shows hunk highlights with modifications"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "lua"

    local diff_utils = require("codecompanion.providers.diff.utils")

    -- Set up buffer with original content
    local removed_lines = {
      "local function calculate(a, b)",
      "  local result = a + b",
      "  return result",
      "end"
    }

    local added_lines = {
      "local function calculate(a, b)",
      "  -- Added validation",
      "  if not a or not b then",
      "    return nil",
      "  end",
      "  local result = a * b",
      "  return result",
      "end"
    }

    -- Set buffer to new content (what the user sees)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, added_lines)

    -- Calculate hunks and apply highlights to show the diff
    local hunks = diff_utils.calculate_hunks(removed_lines, added_lines, 1)
    local ns_id = vim.api.nvim_create_namespace("screenshot_hunk_highlights")

    -- Apply the actual hunk highlights that the code uses
    diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, {
      show_removed = true,
      full_width_removed = true,
      status = "pending"
    })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["DiffUtils Screenshots"]["Shows hunk highlights in buffer"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "python"

    local content = {
      "def process_items(items):",
      "    results = []",
      "    for item in items:",
      "        processed = item.upper()",
      "        results.append(processed)",
      "    return results"
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

    local diff_utils = require("codecompanion.providers.diff.utils")
    local ns_id = vim.api.nvim_create_namespace("screenshot_hunks")

    -- Simulate some hunks with highlights
    local hunks = {
      {
        original_start = 2,
        original_count = 2,
        updated_start = 2,
        updated_count = 3,
        removed_lines = { "    for item in items:", "        result = item.lower()" },
        added_lines = { "    for item in items:", "        processed = item.upper()", "        results.append(processed)" },
        context_before = { "    results = []" },
        context_after = { "    return results" }
      }
    }

    local extmark_ids = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "pending" })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["DiffUtils Screenshots"]["Shows rejected changes highlighting"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "javascript"

    local content = {
      "const config = {",
      "  apiUrl: 'https://api.example.com',",
      "  timeout: 5000,",
      "  retries: 3",
      "};"
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

    local diff_utils = require("codecompanion.providers.diff.utils")
    local ns_id = vim.api.nvim_create_namespace("screenshot_rejected")

    -- Simulate rejected changes
    local hunks = {
      {
        original_start = 2,
        original_count = 1,
        updated_start = 2,
        updated_count = 1,
        removed_lines = { "  apiUrl: 'https://api.example.com'," },
        added_lines = { "  apiUrl: 'https://api.production.com'," },
        context_before = { "const config = {" },
        context_after = { "  timeout: 5000," }
      }
    }

    local extmark_ids = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "rejected" })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["DiffUtils Screenshots"]["Shows complex multi-hunk highlights"] = function()
  child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = "rust"

    local diff_utils = require("codecompanion.providers.diff.utils")

    local removed_lines = {
      "impl Calculator {",
      "    fn add(a: i32, b: i32) -> i32 {",
      "        a + b",
      "    }",
      "",
      "    fn multiply(a: i32, b: i32) -> i32 {",
      "        a * b",
      "    }",
      "}"
    }

    local added_lines = {
      "impl Calculator {",
      "    /// Adds two numbers together",
      "    fn add(a: i32, b: i32) -> i32 {",
      "        a + b",
      "    }",
      "",
      "    /// Multiplies two numbers",
      "    fn multiply(a: i32, b: i32) -> i32 {",
      "        a * b",
      "    }",
      "",
      "    /// Divides two numbers with error handling",
      "    fn divide(a: i32, b: i32) -> Result<i32, &'static str> {",
      "        if b == 0 {",
      "            Err(\"Division by zero\")",
      "        } else {",
      "            Ok(a / b)",
      "        }",
      "    }",
      "}"
    }

    -- Set buffer to new content (what the user sees)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, added_lines)

    -- Calculate hunks and apply highlights using the actual functions
    local hunks = diff_utils.calculate_hunks(removed_lines, added_lines, 2)
    local ns_id = vim.api.nvim_create_namespace("screenshot_multi_hunk")

    -- Apply the actual hunk highlights with complex multi-hunk changes
    diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, {
      show_removed = true,
      full_width_removed = true,
      status = "pending"
    })
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

return T
