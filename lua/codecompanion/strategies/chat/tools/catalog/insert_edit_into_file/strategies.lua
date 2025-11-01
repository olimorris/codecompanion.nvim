--[[
Matching strategies for finding and replacing text

## Matching Strategy Chain:
For each strategy:
1. Find all matches above the confidence threshold
2. If matches are unambiguous (clear winner) → return success
3. If matches are too similar (confidence diff < 0.15) → try next strategy
4. If all strategies tried → use best ambiguous match as fallback

This adaptive approach prevents false positives while ensuring edits eventually succeed.

1. **exact_match** (confidence: 1.0)
   - Line-by-line exact string matching
   - Handles trailing newline normalization
   - Fast path for perfect matches

2. **substring_exact_match** (confidence: 1.0, only with replaceAll)
   - Plain-text substring search (no regex)
   - Only activates when: replaceAll=true AND oldText has NO \n
   - Finds all occurrences in file (max 1000)
   - Perfect for token/keyword replacement (var→let, API renames)

3. **whitespace_normalized** (confidence: 0.95)
   - Handles spacing and indentation differences
   - Removes extra whitespace for comparison

4. **punctuation_normalized** (confidence: 0.93)
   - Tolerates punctuation variations
   - Normalizes common punctuation differences

5. **position_markers** (confidence: 1.0)
   - Special markers: "^" or "<<START>>" (file start)
   - Special markers: "$" or "<<END>>" (file end)

6. **trimmed_lines** (confidence: 0.8)
   - Line-by-line with indentation flexibility
   - Removes common indentation for comparison

7. **block_anchor** (confidence: 0.6) -- This is last resort
   - Uses first/last lines as anchor context
   - Finds blocks by their boundaries

## Key Functions:

- **find_best_match**: Tries all strategies, returns best matches
- **select_best_match**: Picks single match or handles ambiguity
- **apply_replacement**: Applies text replacement (line-based or position-based)
--]]

local constants = require("codecompanion.strategies.chat.tools.catalog.insert_edit_into_file.constants")
local log = require("codecompanion.utils.log")
local text_utils = require("codecompanion.strategies.chat.tools.catalog.insert_edit_into_file.text_utils")

local M = {}

---Apply line-based replacement
---@param content_lines string[] Array of content lines
---@param match table Match information with start_line and end_line
---@param new_text string The replacement text
---@return string The content with replacement applied
local function apply_line_replacement(content_lines, match, new_text)
  local new_content_lines = {}
  local new_text_lines = vim.split(new_text, "\n", { plain = true })

  -- Handle boundary markers specially
  if match.strategy == "start_marker" then
    -- Insert at beginning
    for _, line in ipairs(new_text_lines) do
      table.insert(new_content_lines, line)
    end
    for _, line in ipairs(content_lines) do
      table.insert(new_content_lines, line)
    end
  elseif match.strategy == "end_marker" then
    -- Insert at end
    for _, line in ipairs(content_lines) do
      table.insert(new_content_lines, line)
    end
    for _, line in ipairs(new_text_lines) do
      table.insert(new_content_lines, line)
    end
  else
    -- Normal line replacement
    -- Copy lines before match
    local before_count = match.start_line - 1
    for i = 1, before_count do
      table.insert(new_content_lines, content_lines[i])
    end

    -- Insert new content lines
    for j, line in ipairs(new_text_lines) do
      table.insert(new_content_lines, line)
    end

    -- Copy lines after match
    for i = match.end_line + 1, #content_lines do
      table.insert(new_content_lines, content_lines[i])
    end
  end

  return table.concat(new_content_lines, "\n")
end

---Strategy 1: Exact string matching
---@param content string The content to search within
---@param old_text string The text to find exact matches for
---@return table[] Array of exact matches with position information
function M.exact_match(content, old_text)
  local content_lines = vim.split(content, "\n", { plain = true })
  local old_text_lines = vim.split(old_text, "\n", { plain = true })

  old_text_lines = text_utils.normalize_trailing_newline(old_text_lines)

  local matches = {}

  -- Handle single line vs multi-line differently for efficiency
  if #old_text_lines == 1 then
    -- Single line optimization
    for line_num, line in ipairs(content_lines) do
      if line == old_text_lines[1] then
        table.insert(matches, {
          start_line = line_num,
          end_line = line_num,
          matched_text = old_text,
          confidence = 1.0,
          strategy = "exact_match",
        })
      end
    end
  else
    -- Multi-line search
    for start_line = 1, #content_lines - #old_text_lines + 1 do
      local match_found = true
      local first_mismatch_line = nil

      -- Check if all lines match
      for i = 1, #old_text_lines do
        if content_lines[start_line + i - 1] ~= old_text_lines[i] then
          match_found = false
          first_mismatch_line = i
          break
        end
      end

      if match_found then
        local end_line = start_line + #old_text_lines - 1
        table.insert(matches, {
          start_line = start_line,
          end_line = end_line,
          matched_text = old_text,
          confidence = 1.0,
          strategy = "exact_match",
        })
      end
    end
  end

  return matches
end

---Strategy 2: Enhanced line-by-line with indentation flexibility and better normalization
---@param content string The content to search within
---@param old_text string The text to find matches for using trimmed line comparison
---@return table[] Array of matches found using trimmed line strategy
function M.trimmed_lines(content, old_text)
  local content_lines = vim.split(content, "\n", { plain = true })
  local search_lines = vim.split(old_text, "\n", { plain = true })

  search_lines = text_utils.normalize_trailing_newline(search_lines)

  local matches = {}

  if #search_lines == 0 then
    return matches
  end

  -- Performance safeguards to prevent freezes
  if #content_lines > constants.LIMITS.CONTENT_LINES_STANDARD then
    log:warn(
      "[Insert_edit_into_file Strategies] File too large (%d lines), trimming to %d",
      #content_lines,
      constants.LIMITS.CONTENT_LINES_STANDARD
    )
    content_lines = vim.list_slice(content_lines, 1, constants.LIMITS.CONTENT_LINES_STANDARD)
  end

  if #search_lines > constants.LIMITS.SEARCH_LINES_STANDARD then
    log:warn(
      "[Insert_edit_into_file Strategies] Search text too large (%d lines), aborting trimmed_lines strategy",
      #search_lines
    )
    return matches
  end

  -- Normalize search pattern for indentation-flexible matching
  local normalized_search_lines = text_utils.remove_common_indentation(search_lines)
  local trimmed_search_lines = {}
  for i, line in ipairs(normalized_search_lines) do
    trimmed_search_lines[i] = vim.trim(line)
  end

  local iterations = 0
  for i = 1, #content_lines - #search_lines + 1 do
    iterations = iterations + 1
    if iterations > constants.LIMITS.ITERATIONS_MAX then
      log:warn("[Insert Edit Into File::Strategies] Too many iterations (%d), terminating search early", iterations)
      break
    end

    local content_block = vim.list_slice(content_lines, i, i + #search_lines - 1)
    local normalized_content_lines = text_utils.remove_common_indentation(content_block)

    local match = true
    local confidence = 0

    for j = 1, #search_lines do
      local content_line = vim.trim(normalized_content_lines[j] or "")
      local search_line = trimmed_search_lines[j]

      if content_line == search_line then
        confidence = confidence + 1
      elseif
        text_utils.normalize_whitespace(content_line, "aggressive")
        == text_utils.normalize_whitespace(search_line, "aggressive")
      then
        confidence = confidence + constants.CONFIDENCE.SIMILARITY_THRESHOLD_HIGH
      elseif
        text_utils.similarity_score(content_line, search_line) >= constants.CONFIDENCE.SIMILARITY_THRESHOLD_MEDIUM
      then
        confidence = confidence + constants.CONFIDENCE.SIMILARITY_THRESHOLD_MEDIUM
      elseif
        text_utils.similarity_score(content_line, search_line) >= constants.CONFIDENCE.SIMILARITY_THRESHOLD_LOW
      then
        confidence = confidence + constants.CONFIDENCE.SIMILARITY_THRESHOLD_LOW
      else
        match = false
        break
      end
    end

    if match then
      -- Extract the actual matched text with original formatting
      local matched_lines = {}
      for k = i, i + #search_lines - 1 do
        table.insert(matched_lines, content_lines[k] or "")
      end
      local matched_text = table.concat(matched_lines, "\n")

      table.insert(matches, {
        start_line = i,
        end_line = i + #search_lines - 1,
        matched_text = matched_text,
        confidence = confidence / #search_lines,
        strategy = "trimmed_lines_enhanced",
      })

      -- Early termination if we found enough good matches
      if #matches >= 10 then
        break
      end
    end
  end

  return matches
end

---Strategy 3: Position markers for file boundaries
---@param content string The content to search within
---@param old_text string The text to find using position marker strategy
---@return table[] Array of matches found using position markers
function M.position_markers(content, old_text)
  local matches = {}
  local content_lines = vim.split(content, "\n", { plain = true })

  -- Normalize boundary markers to handle whitespace variations (e.g., "^\n" -> "^")
  local normalized_old_text = vim.trim(old_text)

  if normalized_old_text == "^" or normalized_old_text == "<<START>>" then
    table.insert(matches, {
      start_line = 1,
      end_line = 0, -- Insert before line 1
      matched_text = "",
      confidence = 1.0,
      strategy = "start_marker",
    })
  elseif normalized_old_text == "$" or normalized_old_text == "<<END>>" then
    table.insert(matches, {
      start_line = #content_lines + 1,
      end_line = #content_lines, -- Insert after last line
      matched_text = "",
      confidence = 1.0,
      strategy = "end_marker",
    })
  end

  return matches
end

---Strategy: Punctuation normalization (handles formatter differences)
---@param content string The content to search within
---@param old_text string The text to find using punctuation normalization
---@return table[] Array of matches found using punctuation normalization
function M.punctuation_normalized(content, old_text)
  local matches = {}
  local content_lines = vim.split(content, "\n", { plain = true })
  local old_text_lines = vim.split(old_text, "\n", { plain = true })

  old_text_lines = text_utils.normalize_trailing_newline(old_text_lines)

  -- Handle single line matching
  if #old_text_lines == 1 then
    local normalized_search = text_utils.normalize_punctuation(old_text_lines[1])

    for line_num, line in ipairs(content_lines) do
      local normalized_line = text_utils.normalize_punctuation(line)
      if normalized_line == normalized_search then
        table.insert(matches, {
          start_line = line_num,
          end_line = line_num,
          matched_text = line,
          confidence = 0.93,
          strategy = "punctuation_normalized",
        })
      end
    end
  else
    -- Handle multi-line matching
    for i = 1, #content_lines - #old_text_lines + 1 do
      local match_found = true
      local matched_lines = {}

      for j = 1, #old_text_lines do
        local content_line = content_lines[i + j - 1] or ""
        local search_line = old_text_lines[j]

        if text_utils.normalize_punctuation(content_line) ~= text_utils.normalize_punctuation(search_line) then
          match_found = false
          break
        end
        table.insert(matched_lines, content_line)
      end

      if match_found then
        table.insert(matches, {
          start_line = i,
          end_line = i + #old_text_lines - 1,
          matched_text = table.concat(matched_lines, "\n"),
          confidence = 0.93,
          strategy = "punctuation_normalized",
        })
      end
    end
  end

  return matches
end

---Strategy: Whitespace normalized matching
---@param content string The content to search within
---@param old_text string The text to find using whitespace normalization
---@return table[] Array of matches found using whitespace normalization
function M.whitespace_normalized(content, old_text)
  local matches = {}
  local content_lines = vim.split(content, "\n", { plain = true })
  local old_text_lines = vim.split(old_text, "\n", { plain = true })

  old_text_lines = text_utils.normalize_trailing_newline(old_text_lines)

  -- Handle single line matching
  if #old_text_lines == 1 then
    local normalized_search = text_utils.normalize_whitespace(old_text_lines[1], "simple")

    for line_num, line in ipairs(content_lines) do
      local normalized_line = text_utils.normalize_whitespace(line, "simple")
      if normalized_line == normalized_search then
        table.insert(matches, {
          start_line = line_num,
          end_line = line_num,
          matched_text = line,
          confidence = 0.95,
          strategy = "whitespace_normalized",
        })
      end
    end
  else
    -- Handle multi-line matching
    for i = 1, #content_lines - #old_text_lines + 1 do
      local match_found = true
      local matched_lines = {}

      for j = 1, #old_text_lines do
        local content_line = content_lines[i + j - 1] or ""
        local search_line = old_text_lines[j]

        if
          text_utils.normalize_whitespace(content_line, "simple")
          ~= text_utils.normalize_whitespace(search_line, "simple")
        then
          match_found = false
          break
        end
        table.insert(matched_lines, content_line)
      end

      if match_found then
        table.insert(matches, {
          start_line = i,
          end_line = i + #old_text_lines - 1,
          matched_text = table.concat(matched_lines, "\n"),
          confidence = 0.95,
          strategy = "whitespace_normalized",
        })
      end
    end
  end

  return matches
end

---Enhanced anchor detection using character count
---@param lines string[] Array of lines to search
---@param from_end boolean Whether to search from the end backwards
---@return string|nil, number|nil The meaningful anchor line and its index, or nil if not found
local function get_meaningful_anchor(lines, from_end)
  local start_idx = from_end and #lines or 1
  local end_idx = from_end and 1 or #lines
  local direction = from_end and -1 or 1

  for idx = start_idx, end_idx, direction do
    local line = vim.trim(lines[idx])
    -- Use meaningful line (>10 chars) or non-punctuation-only
    if #line > constants.ANCHOR.MEANINGFUL_LINE_MIN_LENGTH or (#line > 0 and not line:match("^[%s%p]*$")) then
      return line, idx
    end
  end

  -- Fallback to original line if no meaningful line found
  return vim.trim(lines[start_idx]), start_idx
end

---Validate input sizes to prevent performance issues
---@param content string The content to validate
---@param old_text string The search text to validate
---@return table|nil Error result if validation fails, nil if valid
local function validate_input_sizes(content, old_text)
  if #content > constants.LIMITS.FILE_SIZE_MAX then
    log:warn("[Insert Edit Into File::Strategies] Content too large (%d bytes), aborting", #content)
    return {
      success = false,
      error = "File too large for matching strategies",
      attempted_strategies = {},
    }
  end

  if #old_text > constants.LIMITS.SEARCH_TEXT_MAX then
    log:warn("[Insert Edit Into File::Strategies] Search text too large (%d bytes), aborting", #old_text)
    return {
      success = false,
      error = "Search text too large for matching strategies",
      attempted_strategies = {},
    }
  end

  return nil
end

---Check if strategy should be skipped based on configuration
---@param strategy table
---@param replace_all boolean
---@return boolean should_skip
local function should_skip_strategy(strategy, replace_all)
  return strategy.only_replace_all and not replace_all
end

---Execute single strategy with timeout protection
---@param strategy table
---@param content string The content to search within
---@param old_text string Text to find
---@return table matches, number elapsed_ms
local function execute_strategy(strategy, content, old_text)
  local start_time = vim.uv.hrtime()
  local matches = strategy.func(content, old_text)
  local elapsed_ms = (vim.uv.hrtime() - start_time) / 1000000

  if elapsed_ms > constants.LIMITS.STRATEGY_TIMEOUT_MS then
    log:warn("[Insert Edit Into File::Strategies] %s took unusually long: %.2fms", strategy.name, elapsed_ms)
  end

  return matches, elapsed_ms
end

---Filter matches by confidence threshold
---@param matches table[]
---@param min_confidence number
---@return table[] Matches above threshold
local function filter_by_confidence(matches, min_confidence)
  return vim.tbl_filter(function(match)
    return match.confidence >= min_confidence
  end, matches)
end

---Use best ambiguous match as fallback when all strategies exhausted
---@param best_ambiguous_result table
---@return table Result with single best match
local function use_ambiguous_fallback(best_ambiguous_result)
  table.sort(best_ambiguous_result.matches, function(a, b)
    if math.abs(a.confidence - b.confidence) > constants.CONFIDENCE.COMPARISON_EPSILON then
      return a.confidence > b.confidence
    end
    return (a.start_line or 0) < (b.start_line or 0)
  end)

  return {
    success = true,
    matches = { best_ambiguous_result.matches[1] },
    strategy_used = best_ambiguous_result.strategy_used,
    fallback_used = true,
  }
end

---Get all available strategies with their configurations
---@return table[] Array of strategy configurations
local function get_all_strategies()
  return {
    { name = "exact_match", func = M.exact_match, min_confidence = constants.CONFIDENCE.EXACT_MATCH },
    {
      name = "substring_exact_match",
      func = M.substring_exact_match,
      min_confidence = constants.CONFIDENCE.SUBSTRING_EXACT_MATCH,
      only_replace_all = true,
    },
    {
      name = "whitespace_normalized",
      func = M.whitespace_normalized,
      min_confidence = constants.CONFIDENCE.WHITESPACE_NORMALIZED,
    },
    {
      name = "punctuation_normalized",
      func = M.punctuation_normalized,
      min_confidence = constants.CONFIDENCE.PUNCTUATION_NORMALIZED,
    },
    { name = "position_markers", func = M.position_markers, min_confidence = constants.CONFIDENCE.POSITION_MARKERS },
    { name = "trimmed_lines", func = M.trimmed_lines, min_confidence = constants.CONFIDENCE.TRIMMED_LINES_MIN },
    { name = "block_anchor", func = M.block_anchor, min_confidence = constants.CONFIDENCE.BLOCK_ANCHOR_MIN },
  }
end

---Strategy 4: Substring exact match for replaceAll operations
---@param content string The content to search within
---@param old_text string The substring to find all occurrences of
---@return table[] Array of matches found using substring exact match
function M.substring_exact_match(content, old_text)
  local matches = {}

  -- Only use for simple substring patterns (no newlines)
  if old_text:find("\n") then
    return matches
  end

  if old_text == "" then
    return matches
  end

  local start = 1
  local match_count = 0

  while match_count < constants.LIMITS.SUBSTRING_MATCHES_MAX do
    local pos = content:find(old_text, start, true) -- plain text search
    if not pos then
      break
    end

    -- Convert byte position to line-based position
    local line_num = select(2, content:sub(1, pos):gsub("\n", "\n")) + 1

    table.insert(matches, {
      start_pos = pos,
      end_pos = pos + #old_text - 1,
      start_line = line_num,
      end_line = line_num,
      matched_text = old_text,
      confidence = 1.0,
      strategy = "substring_exact_match",
    })

    match_count = match_count + 1
    start = pos + #old_text -- Jump ahead by match length
  end

  if match_count >= constants.LIMITS.SUBSTRING_MATCHES_MAX then
    log:warn("[Insert Edit Into File::Strategies] Hit limit of %d matches", constants.LIMITS.SUBSTRING_MATCHES_MAX)
  end

  return matches
end

---Strategy 5: Block anchor using first and last lines
---@param content string The content to search within
---@param old_text string The text block to find using anchor-based matching
---@return table[] Array of matches found using block anchor strategy
function M.block_anchor(content, old_text)
  -- Normalize empty lines for better LLM matching (applied before line splitting)
  local normalized_content = text_utils.normalize_empty_lines(content)
  local normalized_old_text = text_utils.normalize_empty_lines(old_text)

  local content_lines = vim.split(normalized_content, "\n", { plain = true })
  local search_lines = vim.split(normalized_old_text, "\n", { plain = true })

  -- Handle trailing newline normalization
  search_lines = text_utils.normalize_trailing_newline(search_lines)

  local matches = {}

  if #search_lines < 2 then
    return matches
  end

  -- Performance safeguards
  if #content_lines > constants.LIMITS.CONTENT_LINES_BLOCK_ANCHOR then
    log:warn(
      "[Block Anchor Enhanced] File too large (%d lines), limiting to %d",
      #content_lines,
      constants.LIMITS.CONTENT_LINES_BLOCK_ANCHOR
    )
    content_lines = vim.list_slice(content_lines, 1, constants.LIMITS.CONTENT_LINES_BLOCK_ANCHOR)
  end

  if #search_lines > constants.LIMITS.SEARCH_LINES_BLOCK_ANCHOR then
    log:warn("[Insert Edit Into File::Strategies] Search block too large (%d lines), aborting", #search_lines)
    return matches
  end

  -- Use enhanced anchor detection
  local first_line, first_idx = get_meaningful_anchor(search_lines, false)
  local last_line, last_idx = get_meaningful_anchor(search_lines, true)

  -- Pre-compute trimmed content lines for performance
  local trimmed_content_lines = {}
  for i, line in ipairs(content_lines) do
    trimmed_content_lines[i] = vim.trim(line)
  end

  local anchor_pairs_checked = 0

  -- Find anchor pairs with exact first/last line matches
  for i = 1, #content_lines do
    if trimmed_content_lines[i] == first_line then
      -- Calculate expected end position based on anchor positions
      local expected_end = i + (last_idx - first_idx)

      -- Check if we can fit the entire block
      if expected_end <= #content_lines then
        -- Check if last line matches at expected position
        if expected_end <= #trimmed_content_lines and trimmed_content_lines[expected_end] == last_line then
          anchor_pairs_checked = anchor_pairs_checked + 1

          -- Calculate fuzzy confidence for middle lines
          local middle_confidence = 0
          local middle_lines_count = math.max(1, last_idx - first_idx - 1)

          if last_idx > first_idx + 1 then
            for j = first_idx + 1, last_idx - 1 do
              local content_line_idx = i + (j - first_idx)
              local content_line = trimmed_content_lines[content_line_idx] or ""
              local search_line = vim.trim(search_lines[j])

              local line_similarity = text_utils.calculate_line_similarity(content_line, search_line)
              middle_confidence = middle_confidence + line_similarity
            end
          else
            -- Only 2 meaningful lines total, perfect match
            middle_confidence = 1.0
            middle_lines_count = 1
          end

          local avg_middle_confidence = middle_confidence / middle_lines_count
          local total_confidence = (1.0 + avg_middle_confidence + 1.0) / 3 -- first + middle + last

          -- Use confidence threshold
          if total_confidence >= constants.CONFIDENCE.BLOCK_ANCHOR_CONFIDENCE_MIN then
            local matched_lines = {}
            for k = i, expected_end do
              table.insert(matched_lines, content_lines[k] or "")
            end
            local matched_text = table.concat(matched_lines, "\n")

            table.insert(matches, {
              start_line = i,
              end_line = expected_end,
              matched_text = matched_text,
              confidence = total_confidence,
              strategy = "block_anchor_fuzzy_enhanced",
            })
          end

          -- Safety check to prevent infinite processing
          if anchor_pairs_checked >= constants.LIMITS.ANCHOR_PAIRS_MAX then
            log:warn(
              "[Insert Edit Into File::Strategies] Checked %d anchor pairs, terminating early",
              anchor_pairs_checked
            )
            break
          end
        end
      end
    end
  end

  return matches
end

---Main strategy executor - tries strategies in order until confident match found
---@param content string The content to search within
---@param old_text string The text to find the best match for
---@param replace_all? boolean
---@return table Result containing success status, matches, and strategy information
function M.find_best_match(content, old_text, replace_all)
  replace_all = replace_all or false

  local validation_error = validate_input_sizes(content, old_text)
  if validation_error then
    return validation_error
  end

  local all_strategies = get_all_strategies()
  local best_ambiguous_result = nil

  for i, strategy in ipairs(all_strategies) do
    if should_skip_strategy(strategy, replace_all) then
      goto continue
    end

    local matches, elapsed_ms = execute_strategy(strategy, content, old_text)

    local good_matches = filter_by_confidence(matches, strategy.min_confidence)

    if #good_matches > 0 then
      local is_last_strategy = (i == #all_strategies)
      local selection_result = M.select_best_match(good_matches, replace_all)

      if selection_result.should_try_next then
        -- Keep track of this as potential fallback
        if not best_ambiguous_result then
          best_ambiguous_result = {
            matches = good_matches,
            strategy_used = strategy.name,
          }
        end

        if is_last_strategy then
          return use_ambiguous_fallback(best_ambiguous_result)
        else
          goto continue
        end
      end

      if selection_result.success then
        return {
          success = true,
          matches = good_matches,
          strategy_used = strategy.name,
          total_attempts = vim.tbl_keys(all_strategies),
        }
      end
    end

    ::continue::
  end

  -- If we have ambiguous matches from any strategy, use them as last resort
  if best_ambiguous_result then
    return use_ambiguous_fallback(best_ambiguous_result)
  end

  log:debug("[Insert Edit Into File::Strategies] All strategies failed")
  return {
    success = false,
    error = "No confident matches found with any strategy",
    attempted_strategies = vim.tbl_map(function(s)
      return s.name
    end, all_strategies),
  }
end

---Select best match from multiple candidates
---@param matches table[] Array of potential matches to choose from
---@param replace_all boolean Whether to select all matches or just the best one
---@return table Result containing success status and selected match(es)
function M.select_best_match(matches, replace_all)
  if #matches == 0 then
    return { success = false, error = "No matches provided" }
  end

  if #matches == 1 then
    return { success = true, selected = matches[1], selection_reason = "single_match" }
  end

  if replace_all then
    return { success = true, selected = matches, selection_reason = "replace_all" }
  end

  -- Multiple matches - try to pick the best one automatically
  table.sort(matches, function(a, b)
    if math.abs(a.confidence - b.confidence) > constants.CONFIDENCE.COMPARISON_EPSILON * 10 then
      return a.confidence > b.confidence
    end
    -- Tie-breaker: prefer earlier occurrence
    return (a.start_line or 0) < (b.start_line or 0)
  end)

  local best_match = matches[1]
  local second_best = matches[2]

  -- Check if matches are too ambiguous - signal to try next strategy
  if math.abs(best_match.confidence - second_best.confidence) < constants.CONFIDENCE.AMBIGUITY_THRESHOLD then
    return {
      success = false,
      error = "ambiguous_matches",
      should_try_next = true,
      matches = matches,
      suggestion = "Matches are too similar, trying next strategy for better disambiguation",
    }
  end

  -- Clear winner - use it
  return {
    success = true,
    selected = best_match,
    selection_reason = "high_confidence_winner",
    auto_selected = true,
  }
end

---Apply replacement to content using line-based or byte-based operations
---@param content string The original content
---@param match table|table[] The match or matches to replace
---@param new_text string The replacement text
---@return string The content with replacements applied
function M.apply_replacement(content, match, new_text)
  local content_lines = vim.split(content, "\n", { plain = true })

  if type(match) == "table" and match[1] then
    -- Multiple matches (replace_all case)
    -- Check if these are substring matches (have start_pos/end_pos)
    local first_match = match[1]
    if first_match.strategy == "substring_exact_match" and first_match.start_pos then
      -- Sort by position in reverse order (from end to start)
      local sorted_matches = {}
      for _, m in ipairs(match) do
        table.insert(sorted_matches, m)
      end
      table.sort(sorted_matches, function(a, b)
        return a.start_pos > b.start_pos
      end)

      -- Apply replacements from end to start to maintain positions
      local current_content = content
      for _, m in ipairs(sorted_matches) do
        local before = current_content:sub(1, m.start_pos - 1)
        local after = current_content:sub(m.end_pos + 1)
        current_content = before .. new_text .. after
      end

      return current_content
    end

    -- Line-based replacement for other strategies
    local line_matches = {}
    for _, m in ipairs(match) do
      if m.start_line and m.end_line then
        table.insert(line_matches, m)
      end
    end

    -- Sort matches by line position (reverse order to maintain line numbers)
    table.sort(line_matches, function(a, b)
      return a.start_line > b.start_line
    end)

    -- Apply replacements from bottom to top to maintain line numbers
    local current_content = content
    for _, m in ipairs(line_matches) do
      current_content = apply_line_replacement(vim.split(current_content, "\n", { plain = true }), m, new_text)
    end

    return current_content
  else
    -- Single match
    -- Check if this is a substring match
    if match.strategy == "substring_exact_match" and match.start_pos then
      local before = content:sub(1, match.start_pos - 1)
      local after = content:sub(match.end_pos + 1)
      return before .. new_text .. after
    end

    if match.start_line and match.end_line then
      -- Line-based match (from exact_match or other line-based strategies)
      return apply_line_replacement(content_lines, match, new_text)
    else
      return content
    end
  end
end

return M
