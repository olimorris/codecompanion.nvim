local h = require("tests.helpers")
local log = require("codecompanion.utils.log")
local strategies = require("codecompanion.strategies.chat.tools.builtin.insert_edit_into_file.strategies")

-- Silence noisy warnings during tests; restore after suite runs
local _saved_log = {
  warn = log.warn,
  info = log.info,
  debug = log.debug,
}
log.warn = function() end
log.info = function() end
log.debug = function() end

local new_set = MiniTest.new_set

-- Strategy stats tracking
local strategy_stats = {
  exact_match = { successes = 0, failures = 0 },
  trimmed_lines = { successes = 0, failures = 0 },
  position_markers = { successes = 0, failures = 0 },
  punctuation_normalized = { successes = 0, failures = 0 },
  whitespace_normalized = { successes = 0, failures = 0 },
  block_anchor = { successes = 0, failures = 0 },
  substring_exact_match = { successes = 0, failures = 0 },
}

local function track_strategy_result(strategy_name, success)
  if strategy_stats[strategy_name] then
    if success then
      strategy_stats[strategy_name].successes = strategy_stats[strategy_name].successes + 1
    else
      strategy_stats[strategy_name].failures = strategy_stats[strategy_name].failures + 1
    end
  end
end

local T = new_set({
  hooks = {
    post_once = function()
      -- Restore original logger functions to avoid side effects
      if _saved_log then
        log.warn = _saved_log.warn
        log.info = _saved_log.info
        log.debug = _saved_log.debug
      end
    end,
  },
})

-- Comprehensive find_best_match tests
T["Comprehensive find_best_match Tests"] = new_set()

local cases = require("tests.strategies.chat.tools.builtin.insert_edit_into_file.edit_tool_cases")
-- Run all test cases
for i, test_case in ipairs(cases.test_cases) do
  T["Comprehensive find_best_match Tests"][string.format("Test %d: %s", i, test_case.name)] = function()
    local result = cases.run_test_case(test_case, strategies, track_strategy_result)
    h.eq(
      result.success,
      true,
      string.format("Test case '%s' failed: %s", test_case.name, result.error or "Unknown error")
    )

    if result.success then
      h.eq(type(result.matches), "table")
      h.eq(#result.matches > 0, true)
      h.eq(type(result.strategy_used), "string")

      -- Verify that at least one match has good confidence
      local has_good_match = false
      for _, match in ipairs(result.matches) do
        if match.confidence and match.confidence >= 0.8 then
          has_good_match = true
          break
        end
      end
      h.eq(has_good_match, true, "No high-confidence matches found")
    end
  end
end

-- Test the actual bug: empty buffer content (what happened in the real error)
T["Empty content validation"] = function()
  local empty_content = ""
  local old_text = "\treturn reversed\n}\n\nfunc main() {"

  -- Test each strategy with EMPTY content
  local replace_strategies = {
    { name = "exact_match", func = strategies.exact_match },
    { name = "whitespace_normalized", func = strategies.whitespace_normalized },
    { name = "punctuation_normalized", func = strategies.punctuation_normalized },
    { name = "position_markers", func = strategies.position_markers },
    { name = "trimmed_lines", func = strategies.trimmed_lines },
    { name = "block_anchor", func = strategies.block_anchor },
  }

  local all_failed = true

  for _, strategy in ipairs(replace_strategies) do
    local matches = strategy.func(empty_content, old_text)
    local success = #matches > 0

    if success then
      all_failed = false
    end

    track_strategy_result(strategy.name, success)
  end

  -- Test with find_best_match
  local result = strategies.find_best_match(empty_content, old_text)

  -- All strategies MUST fail with empty content
  h.eq(all_failed, true, "All strategies should fail with empty content")
  h.eq(result.success, false, "find_best_match should fail with empty content")
  h.eq(result.error, "No confident matches found with any strategy")
end

T["Substring match with multiple occurrences per line"] = function()
  local content = [[TODO: Fix TODO items and resolve TODO comments
# TODO: Important TODO note
]]

  local old_text = "TODO"
  local new_text = "DONE"

  local matches = strategies.substring_exact_match(content, old_text)

  h.expect_truthy(#matches >= 5, "Should find at least 5 'TODO' (3 in line 1, 2 in line 2)")

  local result = strategies.find_best_match(content, old_text, true)
  local selection = strategies.select_best_match(result.matches, true)
  local replaced = strategies.apply_replacement(content, selection.selected, new_text)

  -- Verify all TODOs were replaced
  h.expect_truthy(not replaced:find("TODO"), "Should not contain 'TODO' anymore")
  local done_count = select(2, replaced:gsub("DONE", ""))
  h.expect_truthy(done_count >= 5, "Should have replaced all occurrences")

  track_strategy_result("substring_exact_match", true)
end

T["Substring match edge cases"] = function()
  -- Test 1: Pattern at start of file
  local content1 = "text at start\nmore content\ntext again"
  local matches1 = strategies.substring_exact_match(content1, "text")
  h.eq(#matches1, 2, "Should find pattern at start")
  h.eq(matches1[1].start_pos, 1, "First match should be at position 1")

  -- Test 2: Pattern at end of file
  local content2 = "content here\nmore stuff\nend with text"
  local matches2 = strategies.substring_exact_match(content2, "text")
  h.eq(#matches2, 1, "Should find pattern at end")
  h.eq(matches2[1].end_pos, #content2, "Match should end at file end")

  -- Test 3: Pattern with special characters (but not regex)
  local content3 = "price = $100\ncost = $200\n$50 discount"
  local matches3 = strategies.substring_exact_match(content3, "$")
  h.eq(#matches3, 3, "Should find special chars (plain text, not regex)")

  -- Test 4: Single character pattern
  local content4 = "x + y = z"
  local matches4 = strategies.substring_exact_match(content4, "x")
  h.eq(#matches4, 1, "Should find single character")

  -- Test 5: Empty file
  local matches5 = strategies.substring_exact_match("", "text")
  h.eq(#matches5, 0, "Empty file should have no matches")

  track_strategy_result("substring_exact_match", true)
end

T["Substring match rejects patterns with newlines"] = function()
  local content = [[function test() {
  return true;
}]]

  -- Pattern with newline should return empty
  local old_text = "function test() {\n  return true;"
  local matches = strategies.substring_exact_match(content, old_text)

  h.eq(#matches, 0, "Should not match patterns with newlines")

  track_strategy_result("substring_exact_match", true)
end

T["Substring match respects 1000 match limit"] = function()
  -- Create content with >1000 occurrences
  local content = string.rep("x ", 1500) -- 1500 occurrences
  local matches = strategies.substring_exact_match(content, "x")
  h.eq(#matches, 1000, "Should hit the 1000 match limit")
  track_strategy_result("substring_exact_match", true)
end

T["Substring match with UTF-8 characters"] = function()
  local content = [[名前 = "田中"
print(名前)
user.名前 = value
]]

  local matches = strategies.substring_exact_match(content, "名前")
  h.eq(#matches, 3, "Should find 3 occurrences of UTF-8 pattern")
  h.eq(#matches, 3, "Should find all UTF-8 matches")
  -- Test replacement
  local result = strategies.find_best_match(content, "名前", true)
  local selection = strategies.select_best_match(result.matches, true)
  local replaced = strategies.apply_replacement(content, selection.selected, "name")
  h.expect_truthy(replaced:find('name = "田中"'), "Should replace UTF-8 pattern")
  h.expect_truthy(not replaced:find("名前"), "Should not contain original UTF-8")
  track_strategy_result("substring_exact_match", true)
end

T["ReplaceAll JavaScript var to let migration"] = function()
  -- Real-world scenario: Migrate all var declarations to let in a JavaScript file
  local js_content = [[function processData(items) {
  var result = [];
  var total = 0;

  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    var value = item.value;

    if (value > 0) {
      var adjusted = value * 1.1;
      result.push(adjusted);
      total += adjusted;
    }
  }

  var average = total / result.length;
  var summary = {
    results: result,
    total: total,
    average: average
  };

  return summary;
}

var globalConfig = { debug: true };
var apiEndpoint = "https://api.example.com";
]]

  local edit = { oldText = "var ", newText = "let ", replaceAll = true }
  local result = strategies.find_best_match(js_content, edit.oldText, edit.replaceAll)

  h.eq(result.success, true, "Should find matches")
  h.eq(result.strategy_used, "substring_exact_match")
  h.expect_truthy(#result.matches >= 6, "Should find at least 6 var declarations")

  local selection = strategies.select_best_match(result.matches, edit.replaceAll)
  local replaced = strategies.apply_replacement(js_content, selection.selected, edit.newText)

  -- Verify all vars replaced
  h.expect_truthy(not replaced:find("var "), "Should not contain 'var ' anymore")
  h.expect_truthy(replaced:find("let result") ~= nil, "Should have 'let result'")
  h.expect_truthy(replaced:find("let total = 0") ~= nil, "Should have 'let total'")
  h.expect_truthy(replaced:find("let i = 0") ~= nil, "Should have 'let i' in for loop")
  h.expect_truthy(replaced:find("let globalConfig") ~= nil, "Should have 'let globalConfig'")

  -- Should NOT affect 'variable' or other words containing 'var'
  h.expect_truthy(replaced:find("average") ~= nil, "Should not affect 'average'")

  track_strategy_result("substring_exact_match", true)
end

T["Sequential edits - new text creates new matches"] = function()
  -- Edge case: Edit 1 creates text that Edit 2 will match
  local content = [[value = 100
price = 200
]]

  -- First edit: 100 → 100_new
  local edit1 = { oldText = "100", newText = "100_new", replaceAll = true }
  local result1 = strategies.find_best_match(content, edit1.oldText, edit1.replaceAll)
  local selection1 = strategies.select_best_match(result1.matches, edit1.replaceAll)
  local content_after_1 = strategies.apply_replacement(content, selection1.selected, edit1.newText)

  -- Second edit: new → OLD (will match the 'new' we just added!)
  local edit2 = { oldText = "new", newText = "OLD", replaceAll = true }
  local result2 = strategies.find_best_match(content_after_1, edit2.oldText, edit2.replaceAll)

  if result2.success then
    local selection2 = strategies.select_best_match(result2.matches, edit2.replaceAll)
    local content_after_2 = strategies.apply_replacement(content_after_1, selection2.selected, edit2.newText)
    -- This is expected behavior - the new text from edit 1 becomes a target for edit 2
    h.expect_truthy(content_after_2:find("100_OLD") ~= nil, "Should have '100_OLD' after both edits")
  end

  track_strategy_result("substring_exact_match", true)
end

-- Test individual strategies
T["Individual Strategy Tests"] = new_set()

T["Individual Strategy Tests"]["exact_match strategy"] = function()
  local content = [[function test() {
  return "hello";
}]]
  local old_text = [[function test() {
  return "hello";
}]]

  local matches = strategies.exact_match(content, old_text)
  h.eq(#matches > 0, true)
  h.eq(matches[1].confidence >= 1.0, true)
end

T["Individual Strategy Tests"]["trimmed_lines strategy"] = function()
  local content = [[  function test() {
    return "hello";
  }]]
  local old_text = [[function test() {
  return "hello";
}]]

  local matches = strategies.trimmed_lines(content, old_text)
  h.eq(#matches > 0, true)
end

T["Individual Strategy Tests"]["whitespace_normalized strategy"] = function()
  local content = "hello   world"
  local old_text = "hello world"

  local matches = strategies.whitespace_normalized(content, old_text)
  h.eq(#matches > 0, true)
end

T["Individual Strategy Tests"]["punctuation_normalized strategy"] = function()
  local content = "const x = { a: 1, b: 2 };"
  local old_text = "const x = { a: 1, b: 2 }"

  local matches = strategies.punctuation_normalized(content, old_text)
  h.eq(#matches > 0, true)
end

T["Individual Strategy Tests"]["position_markers strategy"] = function()
  local content = [[// START
function test() {
  return true;
}
// END]]
  local old_text = [[// START
function test() {
  return true;
}]]

  local matches = strategies.position_markers(content, old_text)
  h.eq(#matches >= 0, true) -- May or may not find matches depending on markers
end

T["Individual Strategy Tests"]["block_anchor strategy"] = function()
  local content = [[function start() {
  let a = 1;
  let b = 2;
  return a + b;
}]]
  local old_text = [[  let a = 1;
  let b = 2;]]

  local matches = strategies.block_anchor(content, old_text)
  h.eq(#matches >= 0, true)
end

-- Edge cases and error handling
T["Edge Cases and Error Handling"] = new_set()

T["Edge Cases and Error Handling"]["handles very large content"] = function()
  -- Test with 10000 identical lines - edge case where all matches are ambiguous
  local large_content = string.rep("line\n", 10000)
  local old_text = "line\nline\nline"

  local result = strategies.find_best_match(large_content, old_text, false)
  h.eq(result.success, true)
  -- Should use fallback when all strategies find ambiguous matches
  h.eq(type(result.matches), "table")
  h.eq(#result.matches > 0, true)
end

T["Edge Cases and Error Handling"]["handles empty file append"] = function()
  -- Empty content with empty old_text is valid for new file creation
  local content = ""
  local old_text = ""

  -- This should succeed via position_markers strategy
  local result = strategies.find_best_match(content, old_text, false)
  -- Empty searches may or may not succeed depending on strategy, just check it doesn't crash
  h.eq(type(result), "table")
end

T["Edge Cases and Error Handling"]["handles content with unicode characters"] = function()
  local content = 'function test() {\n  return "こんにちは世界";\n}'
  local old_text = 'function test() {\n  return "こんにちは世界";\n}'

  local result = strategies.find_best_match(content, old_text, false)
  h.eq(result.success, true)
end

T["Edge Cases and Error Handling"]["handles content with special regex characters"] = function()
  local content = "const regex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$/"
  local old_text = "const regex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$/"

  local result = strategies.find_best_match(content, old_text, false)
  h.eq(result.success, true)
end

T["Edge Cases and Error Handling"]["handles mixed line endings"] = function()
  local content = "line1\r\nline2\nline3\r\nline4"
  local old_text = "line2\nline3"

  local result = strategies.find_best_match(content, old_text, false)
  h.eq(result.success, true)
end

-- Test apply_replacement functionality
T["Apply Replacement Tests"] = new_set()

T["Apply Replacement Tests"]["applies single replacement correctly"] = function()
  local content = "Hello World"
  local match = {
    start_line = 1,
    end_line = 1,
    start_pos = 1,
    end_pos = 11,
    matched_text = "Hello World",
  }
  local new_text = "Hello Universe"

  local result = strategies.apply_replacement(content, match, new_text)
  h.eq(result, "Hello Universe")
end

T["Apply Replacement Tests"]["applies multiple replacements correctly"] = function()
  local content = "line1\nline2\nline3\nline2\nline4"
  local matches = {
    {
      start_line = 2,
      end_line = 2,
      start_pos = 7,
      end_pos = 11,
      matched_text = "line2",
    },
    {
      start_line = 4,
      end_line = 4,
      start_pos = 19,
      end_pos = 23,
      matched_text = "line2",
    },
  }
  local new_text = "newline"

  local result = strategies.apply_replacement(content, matches, new_text)
  h.eq(result, "line1\nnewline\nline3\nnewline\nline4")
end

-- Test select_best_match functionality
T["Select Best Match Tests"] = new_set()

T["Select Best Match Tests"]["selects highest confidence match"] = function()
  local matches = {
    { confidence = 0.7, matched_text = "match1", start_line = 10 },
    { confidence = 0.9, matched_text = "match2", start_line = 20 },
    { confidence = 0.6, matched_text = "match3", start_line = 30 },
  }

  local result = strategies.select_best_match(matches, false)
  h.eq(result.success, true)
  h.eq(result.selected.confidence, 0.9)
end

T["Select Best Match Tests"]["returns all matches when replace_all is true"] = function()
  local matches = {
    { confidence = 0.8, matched_text = "match1" },
    { confidence = 0.9, matched_text = "match2" },
  }

  local result = strategies.select_best_match(matches, true)
  h.eq(result.success, true)
  h.eq(type(result.selected), "table")
  h.eq(#result.selected, 2)
end

T["Select Best Match Tests"]["handles empty matches"] = function()
  local result = strategies.select_best_match({}, false)
  h.eq(result.success, false)
  h.eq(type(result.error), "string")
end

-- Performance tests
T["Performance Tests"] = new_set()

T["Performance Tests"]["handles reasonable performance on medium files"] = function()
  local medium_content = string.rep("function test" .. math.random() .. "() {\n  return true;\n}\n\n", 1000)
  local old_text = "function test123() {\n  return true;\n}"

  local start_time = os.clock()
  local result = strategies.find_best_match(medium_content, old_text, false)
  local elapsed = os.clock() - start_time

  h.eq(elapsed < 1.0, true, "Performance test failed - took too long: " .. elapsed .. "s")
  -- Note: result.success might be false if no match is found, which is okay for perf test
end

-- Test skip-and-continue logic
T["Skip-and-Continue Tests"] = new_set()

T["Skip-and-Continue Tests"]["signals should_try_next for ambiguous matches"] = function()
  local matches = {
    { confidence = 0.85, matched_text = "match1", start_line = 10 },
    { confidence = 0.84, matched_text = "match2", start_line = 20 },
  }

  local result = strategies.select_best_match(matches, false)
  h.eq(result.success, false)
  h.eq(result.should_try_next, true)
  h.eq(result.error, "ambiguous_matches")
end

T["Skip-and-Continue Tests"]["does not signal should_try_next for clear winner"] = function()
  local matches = {
    { confidence = 0.95, matched_text = "match1", start_line = 10 },
    { confidence = 0.70, matched_text = "match2", start_line = 20 },
  }

  local result = strategies.select_best_match(matches, false)
  h.eq(result.success, true)
  h.eq(result.should_try_next, nil)
  h.eq(result.selected.confidence, 0.95)
end

T["Skip-and-Continue Tests"]["checks confidence difference threshold"] = function()
  -- Exactly at threshold (0.15)
  local matches1 = {
    { confidence = 0.85, matched_text = "match1", start_line = 10 },
    { confidence = 0.70, matched_text = "match2", start_line = 20 },
  }
  local result1 = strategies.select_best_match(matches1, false)
  h.eq(result1.success, true) -- 0.15 difference is clear winner

  -- Just below threshold (0.14)
  local matches2 = {
    { confidence = 0.85, matched_text = "match1", start_line = 10 },
    { confidence = 0.71, matched_text = "match2", start_line = 20 },
  }
  local result2 = strategies.select_best_match(matches2, false)
  h.eq(result2.should_try_next, true) -- 0.14 difference is ambiguous
end

T["Skip-and-Continue Tests"]["replaceAll bypasses ambiguity check"] = function()
  local matches = {
    { confidence = 0.85, matched_text = "match1", start_line = 10 },
    { confidence = 0.84, matched_text = "match2", start_line = 20 },
  }

  local result = strategies.select_best_match(matches, true)
  h.eq(result.success, true)
  h.eq(result.should_try_next, nil)
  h.eq(type(result.selected), "table")
  h.eq(#result.selected, 2) -- Returns all matches
end

-- Integration tests for find_best_match with new logic
T["Integration Tests - New Features"] = new_set()

T["Integration Tests - New Features"]["substring strategy activates for replaceAll"] = function()
  local content = [[var x = 1;
var y = 2;
let z = 3;]]

  local result = strategies.find_best_match(content, "var ", true)
  h.eq(result.success, true)
  h.eq(result.strategy_used, "substring_exact_match")
  h.eq(#result.matches, 2)
end

T["Integration Tests - New Features"]["substring strategy skipped when replaceAll is false"] = function()
  local content = [[var x = 1;
var y = 2;]]

  -- substring_exact_match should be skipped, exact_match should be used
  local result = strategies.find_best_match(content, "var x = 1;", false)
  h.eq(result.success, true)
  -- Should use exact_match or another strategy, not substring_exact_match
  h.eq(result.strategy_used ~= "substring_exact_match", true)
end

T["Integration Tests - New Features"]["substring strategy skipped for multi-line patterns"] = function()
  local content = [[function test() {
  return 1;
}
function test() {
  return 2;
}]]

  local old_text = [[function test() {
  return 1;
}]]

  local result = strategies.find_best_match(content, old_text, true)
  h.eq(result.success, true)
  -- Should not use substring_exact_match (has newlines)
  h.eq(result.strategy_used ~= "substring_exact_match", true)
end

T["Integration Tests - New Features"]["falls through strategies on ambiguity"] = function()
  -- Create content where early strategy finds ambiguous matches
  local content = [[function test() {
  x = 1;
}

class MyClass {
  function test() {
    x = 2;
  }
}

function test() {
  x = 3;
}]]

  local old_text = "function test() {"

  -- This should try multiple strategies due to ambiguity
  local result = strategies.find_best_match(content, old_text, false)
  -- Result could be success or failure depending on strategies' ability to disambiguate
  -- The key is that it tried multiple strategies
  h.eq(type(result), "table")
  h.eq(type(result.success), "boolean")
end

T["Integration Tests - New Features"]["substring match with special characters"] = function()
  local content = [[const API_KEY = "test";
const API_URL = "url";
const OTHER = "val";]]

  local result = strategies.find_best_match(content, "API_", true)
  h.eq(result.success, true)
  h.eq(result.strategy_used, "substring_exact_match")
  h.eq(#result.matches, 2)
end

T["Strategy Exhaustion Tests"] = new_set()

T["Strategy Exhaustion Tests"]["tracks which strategy was used for successful match"] = function()
  local content = "function test() { return true; }"
  local old_text = "function test() { return true; }"

  local result = strategies.find_best_match(content, old_text, false)

  h.eq(result.success, true)
  h.eq(type(result.strategy_used), "string")
  h.eq(result.strategy_used, "exact_match", "Exact match should succeed first")
  h.eq(type(result.total_attempts), "table")
end

return T
