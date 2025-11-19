local h = require("tests.helpers")
local match_selector = require("codecompanion.strategies.chat.tools.catalog.insert_edit_into_file.match_selector")

local new_set = MiniTest.new_set

local T = new_set()

T["Format Helpful Error Tests"] = new_set()

T["Format Helpful Error Tests"]["formats basic error message"] = function()
  local failed_result = {
    failed_at_edit = 1,
    error = "No confident matches found",
  }
  local original_edits = {
    { oldText = "function test() {\n  return true;\n}" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("Edit #1 failed: No confident matches found", error_msg)
  h.expect_contains("Failed edit was looking for:", error_msg)
  h.expect_contains("function test() {", error_msg)
end

T["Format Helpful Error Tests"]["handles ambiguous matches error"] = function()
  local failed_result = {
    failed_at_edit = 2,
    error = "ambiguous_matches",
    matches = {
      {
        confidence = 0.9,
        start_line = 5,
        matched_text = "function process() {\n  return data;\n}",
      },
      {
        confidence = 0.8,
        start_line = 15,
        matched_text = "function process() {\n  return result;\n}",
      },
      {
        confidence = 0.7,
        start_line = 25,
        matched_text = "function processData() {\n  return info;\n}",
      },
    },
  }
  local original_edits = {
    { oldText = "first edit" },
    { oldText = "function process() {\n  return data;\n}" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("Edit #2 failed: ambiguous_matches", error_msg)
  h.expect_contains("Found 3 similar matches:", error_msg)
  h.expect_contains("1. Confidence 90% (line 5):", error_msg)
  h.expect_contains("2. Confidence 80% (line 15):", error_msg)
  h.expect_contains("3. Confidence 70% (line 25):", error_msg)
  h.expect_contains("To fix this:", error_msg)
  h.expect_contains("Add more surrounding context", error_msg)
  h.expect_contains("set 'replaceAll: true'", error_msg)
end

T["Format Helpful Error Tests"]["limits matches display to 5"] = function()
  local matches = {}
  for i = 1, 8 do
    table.insert(matches, {
      confidence = 0.9 - (i * 0.1),
      start_line = i * 10,
      matched_text = string.format("match %d content", i),
    })
  end

  local failed_result = {
    failed_at_edit = 1,
    error = "ambiguous_matches",
    matches = matches,
  }
  local original_edits = {
    { oldText = "test pattern" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("... and 3 more matches", error_msg)
  -- Should not show match 6, 7, 8
  h.eq(error_msg:find("match 6"), nil, "Should not show match 6 and beyond")
end

T["Format Helpful Error Tests"]["handles no confident matches error"] = function()
  local failed_result = {
    failed_at_edit = 1,
    error = "No confident matches found with any strategy",
  }
  local original_edits = {
    { oldText = "missing text" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("The text could not be found in the file", error_msg)
  h.expect_contains("different formatting (spaces, tabs, line breaks)", error_msg)
  h.expect_contains("Use the read_file tool", error_msg)
  h.expect_contains("Copy the exact text from the file", error_msg)
end

T["Format Helpful Error Tests"]["handles conflicting edits error"] = function()
  local failed_result = {
    failed_at_edit = 2,
    error = "conflicting_edits",
  }
  local original_edits = {
    { oldText = "first edit" },
    { oldText = "conflicting edit" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("Multiple edits are trying to modify overlapping text", error_msg)
  h.expect_contains("combine conflicting edits into a single edit", error_msg)
end

T["Format Helpful Error Tests"]["includes partial results information"] = function()
  local failed_result = {
    failed_at_edit = 3,
    error = "some error",
    partial_results = { "result1", "result2" },
  }
  local original_edits = {
    { oldText = "edit1" },
    { oldText = "edit2" },
    { oldText = "edit3" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("2 edit(s) before this one were processed successfully", error_msg)
end

T["Format Helpful Error Tests"]["handles long oldText preview"] = function()
  local long_text = string.rep("This is a very long text pattern ", 10) -- > 100 chars
  local failed_result = {
    failed_at_edit = 1,
    error = "test error",
  }
  local original_edits = {
    { oldText = long_text },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("...", error_msg) -- Should be truncated
  local truncated_part = error_msg:match("Failed edit was looking for: (.-%.%.%.)")
  h.eq(truncated_part ~= nil, true, "Should contain truncated text")
  if truncated_part then
    h.eq(#truncated_part, 103, "Should be exactly 100 chars + '...'") -- 100 + 3
  end
end

T["Format Helpful Error Tests"]["handles unknown error"] = function()
  local failed_result = {
    failed_at_edit = 2, -- Point to non-existent edit
    error = "some error",
  }
  local original_edits = {
    { oldText = "test" }, -- Only one edit, so index 2 doesn't exist
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.eq(error_msg, "Unknown error occurred during edit processing")
end

T["Detect Edit Conflicts Tests"] = new_set()

T["Detect Edit Conflicts Tests"]["detects overlapping edits"] = function()
  local content = "line1\nline2\nline3\nline4\nline5"
  local edits = {
    { oldText = "line2\nline3" },
    { oldText = "line3\nline4" },
  }

  local conflicts = match_selector.detect_edit_conflicts(content, edits)

  h.eq(#conflicts, 1, "Should detect one conflict")
  h.eq(conflicts[1].edit1_index, 1)
  h.eq(conflicts[1].edit2_index, 2)
  h.expect_contains("overlapping text", conflicts[1].description)
end

T["Detect Edit Conflicts Tests"]["handles non-overlapping edits"] = function()
  local content = "line1\nline2\nline3\nline4\nline5"
  local edits = {
    { oldText = "line1" },
    { oldText = "line4" },
  }

  local conflicts = match_selector.detect_edit_conflicts(content, edits)

  h.eq(#conflicts, 0, "Should not detect conflicts for non-overlapping edits")
end

T["Detect Edit Conflicts Tests"]["handles edits with text not found"] = function()
  local content = "existing content"
  local edits = {
    { oldText = "non-existent text 1" },
    { oldText = "non-existent text 2" },
  }

  local conflicts = match_selector.detect_edit_conflicts(content, edits)

  h.eq(#conflicts, 0, "Should not detect conflicts when text is not found")
end

T["Error Building Pattern Tests"] = new_set()

T["Error Building Pattern Tests"]["builds error progressively with append function"] = function()
  -- Test that the append function works as expected by examining the structure
  local failed_result = {
    failed_at_edit = 1,
    error = "test_error",
  }
  local original_edits = {
    { oldText = "test" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  -- The error should be built progressively using the append function
  -- Verify the structure by checking that multiple parts are combined
  local lines = vim.split(error_msg, "\n")
  h.eq(#lines >= 2, true, "Should have multiple lines from progressive building")
  h.expect_contains("Edit #1 failed: test_error", lines[1])
  h.expect_contains("Failed edit was looking for:", lines[2])
end

T["Error Building Pattern Tests"]["handles conditional sections correctly"] = function()
  -- Test with ambiguous matches to see conditional section
  local failed_result = {
    failed_at_edit = 1,
    error = "ambiguous_matches",
    matches = {
      { confidence = 0.9, start_line = 1, matched_text = "match1" },
    },
  }
  local original_edits = {
    { oldText = "test" },
  }

  local error_msg = match_selector.format_helpful_error(failed_result, original_edits)

  h.expect_contains("Found 1 similar matches:", error_msg)
  h.expect_contains("To fix this:", error_msg)

  -- Test without matches to ensure conditional section is not added
  failed_result.matches = nil
  local error_msg2 = match_selector.format_helpful_error(failed_result, original_edits)
  h.eq(error_msg2:find("Found .* similar matches:"), nil, "Should not show matches section when no matches")
end

return T
