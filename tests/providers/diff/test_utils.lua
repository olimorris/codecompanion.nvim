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
  local old_lines = { "line 1", "line 2" }
  local new_lines = { "line 1", "line 2", "line 3" }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)

  h.eq(type(hunks), "table")
  h.expect_truthy(#hunks > 0)
end

T["DiffUtils"]["calculate_hunks - detects simple deletion"] = function()
  local old_lines = { "line 1", "line 2", "line 3" }
  local new_lines = { "line 1", "line 3" }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)

  h.eq(type(hunks), "table")
  h.expect_truthy(#hunks > 0)
end

T["DiffUtils"]["calculate_hunks - detects modification"] = function()
  local old_lines = { "line 1", "old line 2", "line 3" }
  local new_lines = { "line 1", "new line 2", "line 3" }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)

  h.eq(type(hunks), "table")
  h.expect_truthy(#hunks > 0)
end

T["DiffUtils"]["calculate_hunks - returns empty for identical content"] = function()
  local old_lines = { "line 1", "line 2", "line 3" }
  local new_lines = { "line 1", "line 2", "line 3" }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)

  h.eq(type(hunks), "table")
  h.eq(#hunks, 0)
end

T["DiffUtils"]["calculate_hunks - handles empty content"] = function()
  local old_lines = {}
  local new_lines = { "new line" }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)

  h.eq(type(hunks), "table")
end

T["DiffUtils"]["calculate_hunks - respects context lines parameter"] = function()
  local old_lines = { "line 1", "line 2", "line 3", "line 4", "line 5" }
  local new_lines = { "line 1", "modified line 2", "line 3", "line 4", "line 5" }

  local hunks_default = diff_utils.calculate_hunks(old_lines, new_lines)
  local hunks_context_1 = diff_utils.calculate_hunks(old_lines, new_lines, 1)

  h.eq(type(hunks_default), "table")
  h.eq(type(hunks_context_1), "table")
end

T["DiffUtils"]["calculate_hunks - returns valid hunk structure"] = function()
  local old_lines = { "line 1", "old line", "line 3" }
  local new_lines = { "line 1", "new line", "line 3" }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)

  if #hunks > 0 then
    local hunk = hunks[1]
    h.eq(type(hunk.old_start), "number")
    h.eq(type(hunk.old_count), "number")
    h.eq(type(hunk.new_start), "number")
    h.eq(type(hunk.new_count), "number")
    h.eq(type(hunk.old_lines), "table")
    h.eq(type(hunk.new_lines), "table")
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

  local extmark_ids_pending = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "pending" })
  local extmark_ids_accepted = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "accepted" })
  local extmark_ids_rejected = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id, 0, { status = "rejected" })

  h.eq(type(extmark_ids_pending), "table")
  h.eq(type(extmark_ids_accepted), "table")
  h.eq(type(extmark_ids_rejected), "table")

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["DiffUtils"]["get_sign_highlight_for_change - returns highlight for added lines"] = function()
  local highlight = diff_utils.get_sign_highlight_for_change("added", false, "pending")

  h.eq(type(highlight), "string")
end

T["DiffUtils"]["get_sign_highlight_for_change - returns highlight for removed lines"] = function()
  local highlight = diff_utils.get_sign_highlight_for_change("removed", false, "pending")

  h.eq(type(highlight), "string")
end

T["DiffUtils"]["get_sign_highlight_for_change - returns highlight for modifications"] = function()
  local highlight = diff_utils.get_sign_highlight_for_change("added", true, "pending")

  h.eq(type(highlight), "string")
end

T["DiffUtils"]["get_sign_highlight_for_change - handles rejected status"] = function()
  local highlight = diff_utils.get_sign_highlight_for_change("added", false, "rejected")

  h.eq(highlight, "DiagnosticError")
end

T["DiffUtils"]["get_sign_highlight_for_change - defaults to pending status"] = function()
  local highlight_default = diff_utils.get_sign_highlight_for_change("added", false)
  local highlight_explicit = diff_utils.get_sign_highlight_for_change("added", false, "pending")

  h.eq(highlight_default, highlight_explicit)
end

-- Test contents_equal function
T["DiffUtils"]["contents_equal - returns true for identical content"] = function()
  local content1 = { "line 1", "line 2", "line 3" }
  local content2 = { "line 1", "line 2", "line 3" }
  local result = diff_utils.contents_equal(content1, content2)

  h.eq(result, true)
end

T["DiffUtils"]["contents_equal - returns false for different content"] = function()
  local content1 = { "line 1", "line 2", "line 3" }
  local content2 = { "line 1", "modified line 2", "line 3" }
  local result = diff_utils.contents_equal(content1, content2)

  h.eq(result, false)
end

T["DiffUtils"]["contents_equal - returns false for different lengths"] = function()
  local content1 = { "line 1", "line 2" }
  local content2 = { "line 1", "line 2", "line 3" }
  local result = diff_utils.contents_equal(content1, content2)

  h.eq(result, false)
end

T["DiffUtils"]["contents_equal - handles empty arrays"] = function()
  local content1 = {}
  local content2 = {}
  local result = diff_utils.contents_equal(content1, content2)

  h.eq(result, true)
end

T["DiffUtils"]["contents_equal - handles one empty array"] = function()
  local content1 = {}
  local content2 = { "line 1" }
  local result = diff_utils.contents_equal(content1, content2)

  h.eq(result, false)
end

T["DiffUtils"]["create_unified_diff_display - creates display lines"] = function()
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
  local combined_lines, ranges = diff_utils.create_unified_diff_display(hunks)

  h.eq(type(combined_lines), "table")
  h.eq(type(ranges), "table")
  h.eq(type(ranges.line_types), "table")
  h.eq(type(ranges.hunk_types), "table")
  h.eq(#combined_lines, #ranges.line_types)
  h.eq(#combined_lines, #ranges.hunk_types)
end

T["DiffUtils"]["create_unified_diff_display - handles empty hunks"] = function()
  local combined_lines, ranges = diff_utils.create_unified_diff_display({})

  h.eq(type(combined_lines), "table")
  h.eq(type(ranges), "table")
  h.eq(type(ranges.line_types), "table")
  h.eq(type(ranges.hunk_types), "table")
  h.eq(#combined_lines, 0)
  h.eq(#ranges.line_types, 0)
  h.eq(#ranges.hunk_types, 0)
end

T["DiffUtils"]["create_unified_diff_display - respects options"] = function()
  local hunks = {
    {
      old_start = 1,
      old_count = 1,
      new_start = 1,
      new_count = 1,
      old_lines = { "old line" },
      new_lines = { "new line" },
      context_before = {},
      context_after = {},
    },
  }
  local opts = { show_line_numbers = true }
  local combined_lines, ranges = diff_utils.create_unified_diff_display(hunks, opts)

  h.eq(type(combined_lines), "table")
  h.eq(type(ranges), "table")
  h.eq(type(ranges.line_types), "table")
  h.eq(type(ranges.hunk_types), "table")
end

-- Integration tests
T["DiffUtils"]["integration - full diff workflow"] = function()
  local old_lines = {
    "function hello()",
    "  print('old')",
    "end",
  }
  local new_lines = {
    "function hello()",
    "  print('new')",
    "  print('extra line')",
    "end",
  }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)
  h.expect_truthy(#hunks > 0)

  local bufnr = vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("test_integration")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

  local extmark_ids = diff_utils.apply_hunk_highlights(bufnr, hunks, ns_id)
  h.eq(type(extmark_ids), "table")

  local combined_lines, _ = diff_utils.create_unified_diff_display(hunks)
  h.expect_truthy(#combined_lines > 0)

  h.eq(diff_utils.contents_equal(old_lines, new_lines), false)
  h.eq(diff_utils.contents_equal(old_lines, old_lines), true)

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

T["DiffUtils"]["integration - complex multi-hunk diff"] = function()
  local old_lines = {
    "line 1",
    "line 2 old",
    "line 3",
    "line 4",
    "line 5 old",
    "line 6",
  }
  local new_lines = {
    "line 1",
    "line 2 new",
    "line 3",
    "inserted line",
    "line 4",
    "line 5 new",
    "line 6",
  }

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines)
  h.expect_truthy(#hunks > 0)

  local combined_lines, ranges = diff_utils.create_unified_diff_display(hunks)
  h.expect_truthy(#combined_lines > 0)

  local has_context = false
  for _, line_type in ipairs(ranges.line_types) do
    if line_type == "context" then
      has_context = true
    end
  end

  h.eq(has_context, true)
end

return T
