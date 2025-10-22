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

local log = require("codecompanion.utils.log")

local M = {}

---Levenshtein distance for similarity scoring
---@param a string First string to compare
---@param b string Second string to compare
---@return number The edit distance between the two strings
local function levenshtein_distance(a, b)
  if a == "" then
    return #b
  end
  if b == "" then
    return #a
  end

  local matrix = {}
  for i = 0, #a do
    matrix[i] = { [0] = i }
  end
  for j = 0, #b do
    matrix[0][j] = j
  end

  for i = 1, #a do
    for j = 1, #b do
      local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
      matrix[i][j] = math.min(
        matrix[i - 1][j] + 1, -- deletion
        matrix[i][j - 1] + 1, -- insertion
        matrix[i - 1][j - 1] + cost -- substitution
      )
    end
  end

  return matrix[#a][#b]
end

---Calculate similarity score between two strings (0.0 to 1.0)
---@param a string First string to compare
---@param b string Second string to compare
---@return number Similarity score from 0.0 (no similarity) to 1.0 (identical)
local function similarity_score(a, b)
  if a == b then
    return 1.0
  end
  local max_len = math.max(#a, #b)
  if max_len == 0 then
    return 1.0
  end
  return 1.0 - (levenshtein_distance(a, b) / max_len)
end

---Normalize whitespace for better matching
---@param text string The text to normalize
---@param aggressive boolean Whether to use aggressive normalization
---@return string The normalized text
local function normalize_whitespace(text, aggressive)
  if aggressive then
    -- Remove all extra whitespace, normalize indentation
    return text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  else
    -- Just trim and normalize line endings
    return vim.trim(text):gsub("\r\n", "\n")
  end
end

---Apply line-based replacement
---@param content_lines string[] Array of content lines
---@param match table Match information with start_line and end_line
---@param new_text string The replacement text
---@return string The content with replacement applied
local function apply_line_replacement(content_lines, match, new_text)
  log:trace(
    "Inser_edit_into_file Strategies] Line replacement: lines %d-%d, strategy: %s",
    match.start_line,
    match.end_line,
    match.strategy or "unknown"
  )

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

    log:trace(
      "Inser_edit_into_file Strategies] Replacing %d lines with %d lines",
      match.end_line - match.start_line + 1,
      #new_text_lines
    )

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

  -- Handle trailing newline normalization (like production tools)
  -- Remove empty trailing line if present (handles "text\n" patterns)
  if #old_text_lines >= 2 and old_text_lines[#old_text_lines] == "" then
    old_text_lines = vim.list_slice(old_text_lines, 1, #old_text_lines - 1)
  end

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

  log:debug("Inser_edit_into_file Strategies] Exact match found %d matches", #matches)
  return matches
end

---Strategy 2: Enhanced line-by-line with indentation flexibility and better normalization
---@param content string The content to search within
---@param old_text string The text to find matches for using trimmed line comparison
---@return table[] Array of matches found using trimmed line strategy
function M.trimmed_lines(content, old_text)
  local content_lines = vim.split(content, "\n", { plain = true })
  local search_lines = vim.split(old_text, "\n", { plain = true })

  -- Handle trailing newline normalization (like production tools)
  -- Remove empty trailing line if present (handles "text\n" patterns)
  if #search_lines >= 2 and search_lines[#search_lines] == "" then
    search_lines = vim.list_slice(search_lines, 1, #search_lines - 1)
  end

  local matches = {}

  if #search_lines == 0 then
    return matches
  end

  -- Performance safeguards to prevent freezes
  local max_content_lines = 5000
  local max_search_lines = 200
  local max_iterations = 10000

  if #content_lines > max_content_lines then
    log:warn(
      "Inser_edit_into_file Strategies] File too large (%d lines), trimming to %d",
      #content_lines,
      max_content_lines
    )
    content_lines = vim.list_slice(content_lines, 1, max_content_lines)
  end

  if #search_lines > max_search_lines then
    log:warn(
      "Inser_edit_into_file Strategies] Search text too large (%d lines), aborting trimmed_lines strategy",
      #search_lines
    )
    return matches
  end

  ---Remove common indentation from search pattern (like production tools)
  ---@param lines string[] Array of lines to process
  ---@return string[] Array of lines with common indentation removed
  local function remove_common_indentation(lines)
    local non_empty_lines = vim.tbl_filter(function(line)
      return vim.trim(line) ~= ""
    end, lines)

    if #non_empty_lines == 0 then
      return lines
    end

    -- Find minimum indentation
    local min_indent = math.huge
    for _, line in ipairs(non_empty_lines) do
      local indent = line:match("^(%s*)")
      min_indent = math.min(min_indent, #indent)
    end

    if min_indent == 0 or min_indent == math.huge then
      return lines
    end

    -- Remove common indentation
    local result = {}
    for _, line in ipairs(lines) do
      if vim.trim(line) == "" then
        table.insert(result, line)
      else
        table.insert(result, line:sub(min_indent + 1))
      end
    end
    return result
  end

  -- Normalize search pattern for indentation-flexible matching
  local normalized_search_lines = remove_common_indentation(search_lines)
  local trimmed_search_lines = {}
  for i, line in ipairs(normalized_search_lines) do
    trimmed_search_lines[i] = vim.trim(line)
  end

  local iterations = 0
  for i = 1, #content_lines - #search_lines + 1 do
    iterations = iterations + 1
    if iterations > max_iterations then
      log:warn("Inser_edit_into_file Strategies] Too many iterations (%d), terminating search early", iterations)
      break
    end

    local content_block = vim.list_slice(content_lines, i, i + #search_lines - 1)
    local normalized_content_lines = remove_common_indentation(content_block)

    local match = true
    local confidence = 0

    for j = 1, #search_lines do
      local content_line = vim.trim(normalized_content_lines[j] or "")
      local search_line = trimmed_search_lines[j]

      if content_line == search_line then
        confidence = confidence + 1
      elseif normalize_whitespace(content_line, true) == normalize_whitespace(search_line, true) then
        confidence = confidence + 0.95
      elseif similarity_score(content_line, search_line) >= 0.85 then
        confidence = confidence + 0.85
      elseif similarity_score(content_line, search_line) >= 0.7 then
        confidence = confidence + 0.7
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

  log:debug("Inser_edit_into_file Strategies] Trimmed lines found %d matches", #matches)
  return matches
end

---Strategy 3: Position markers for file boundaries
---@param content string The content to search within
---@param old_text string The text to find using position marker strategy
---@return table[] Array of matches found using position markers
function M.position_markers(content, old_text)
  local matches = {}
  local content_lines = vim.split(content, "\n", { plain = true })

  if old_text == "^" or old_text == "<<START>>" then
    table.insert(matches, {
      start_line = 1,
      end_line = 0, -- Insert before line 1
      matched_text = "",
      confidence = 1.0,
      strategy = "start_marker",
    })
  elseif old_text == "$" or old_text == "<<END>>" then
    table.insert(matches, {
      start_line = #content_lines + 1,
      end_line = #content_lines, -- Insert after last line
      matched_text = "",
      confidence = 1.0,
      strategy = "end_marker",
    })
  end

  log:debug("Inser_edit_into_file Strategies] Position markers found %d matches", #matches)
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

  -- Handle trailing newline normalization
  if #old_text_lines >= 2 and old_text_lines[#old_text_lines] == "" then
    old_text_lines = vim.list_slice(old_text_lines, 1, #old_text_lines - 1)
  end

  ---Normalize punctuation: remove trailing punctuation, normalize spacing
  ---@param text string The text to normalize
  ---@return string The text with normalized punctuation
  local function normalize_punctuation(text)
    return vim
      .trim(text)
      -- Remove trailing commas and semicolons
      :gsub(",%s*$", "")
      :gsub(";%s*$", "")
      -- Normalize comma and semicolon spacing
      :gsub("%s*,%s*", ",")
      :gsub("%s*;%s*", ";")
      -- Normalize parentheses spacing
      :gsub("%s*%(%s*", "(")
      :gsub("%s*%)%s*", ")")
      -- Normalize bracket spacing
      :gsub("%s*%[%s*", "[")
      :gsub("%s*%]%s*", "]")
      -- Normalize brace spacing
      :gsub("%s*{%s*", "{")
      :gsub("%s*}%s*", "}")
  end

  -- Handle single line matching
  if #old_text_lines == 1 then
    local normalized_search = normalize_punctuation(old_text_lines[1])

    for line_num, line in ipairs(content_lines) do
      local normalized_line = normalize_punctuation(line)
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

        if normalize_punctuation(content_line) ~= normalize_punctuation(search_line) then
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

  log:debug("Inser_edit_into_file Strategies] Punctuation normalized found %d matches", #matches)
  return matches
end

---Strategy: Whitespace normalized matching (based on production tools)
---@param content string The content to search within
---@param old_text string The text to find using whitespace normalization
---@return table[] Array of matches found using whitespace normalization
function M.whitespace_normalized(content, old_text)
  local matches = {}
  local content_lines = vim.split(content, "\n", { plain = true })
  local old_text_lines = vim.split(old_text, "\n", { plain = true })

  -- Handle trailing newline normalization
  if #old_text_lines >= 2 and old_text_lines[#old_text_lines] == "" then
    old_text_lines = vim.list_slice(old_text_lines, 1, #old_text_lines - 1)
  end

  ---Normalize whitespace: collapse multiple spaces to single space and trim
  ---@param text string The text to normalize
  ---@return string The text with normalized whitespace
  local function normalize_whitespace(text)
    return vim.trim(text):gsub("%s+", " ")
  end

  -- Handle single line matching
  if #old_text_lines == 1 then
    local normalized_search = normalize_whitespace(old_text_lines[1])

    for line_num, line in ipairs(content_lines) do
      local normalized_line = normalize_whitespace(line)
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

        if normalize_whitespace(content_line) ~= normalize_whitespace(search_line) then
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

  log:debug("Inser_edit_into_file Strategies] Whitespace normalized found %d matches", #matches)
  return matches
end

---Calculate line similarity with better fuzzy matching
---@param line1 string First line to compare
---@param line2 string Second line to compare
---@return number Similarity score between 0 and 1
local function calculate_line_similarity(line1, line2)
  if line1 == line2 then
    return 1.0
  end

  local trimmed1 = vim.trim(line1)
  local trimmed2 = vim.trim(line2)

  if trimmed1 == trimmed2 then
    return 0.95 -- High similarity for whitespace-only differences
  end

  -- Use edit distance for fuzzy comparison
  return similarity_score(trimmed1, trimmed2)
end

---Normalize empty lines for better LLM code block matching (conservative approach)
---@param text string Text to normalize empty lines in
---@return string Text with normalized empty lines
local function normalize_empty_lines(text)
  -- Be more conservative - only normalize multiple consecutive empty lines to single
  -- and trim leading/trailing empty lines to preserve line positions
  local normalized = text

  -- Normalize multiple consecutive empty lines to at most 1
  normalized = normalized:gsub("\n\n\n+", "\n\n")

  -- Trim leading empty lines
  normalized = normalized:gsub("^%s*\n", "")

  -- Trim trailing empty lines
  normalized = normalized:gsub("\n%s*$", "")

  return normalized
end

---Enhanced anchor detection using character count
---@param lines string[] Array of lines to search
---@param from_end boolean Whether to search from the end backwards
---@return string|nil The meaningful anchor line or nil if not found
local function get_meaningful_anchor(lines, from_end)
  local start_idx = from_end and #lines or 1
  local end_idx = from_end and 1 or #lines
  local direction = from_end and -1 or 1

  for idx = start_idx, end_idx, direction do
    local line = vim.trim(lines[idx])
    -- Use meaningful line (>10 chars) or non-punctuation-only
    if #line > 10 or (#line > 0 and not line:match("^[%s%p]*$")) then
      return line, idx
    end
  end

  -- Fallback to original line if no meaningful line found
  return vim.trim(lines[start_idx]), start_idx
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
  local max_matches = 1000
  local match_count = 0

  while match_count < max_matches do
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

  if match_count >= max_matches then
    log:warn("[Substring Exact Match] Hit limit of %d matches", max_matches)
  end

  log:debug("[Substring Exact Match] Found %d total matches", #matches)
  return matches
end

---Strategy 5: Block anchor using first and last lines
---@param content string The content to search within
---@param old_text string The text block to find using anchor-based matching
---@return table[] Array of matches found using block anchor strategy
function M.block_anchor(content, old_text)
  -- Normalize empty lines for better LLM matching (applied before line splitting)
  local normalized_content = normalize_empty_lines(content)
  local normalized_old_text = normalize_empty_lines(old_text)

  local content_lines = vim.split(normalized_content, "\n", { plain = true })
  local search_lines = vim.split(normalized_old_text, "\n", { plain = true })

  -- Handle trailing newline normalization (like production tools)
  if #search_lines >= 2 and search_lines[#search_lines] == "" then
    search_lines = vim.list_slice(search_lines, 1, #search_lines - 1)
  end

  local matches = {}

  if #search_lines < 2 then
    return matches
  end

  -- Performance safeguards
  local max_content_lines = 3000
  local max_search_lines = 100
  local max_anchor_pairs = 50

  if #content_lines > max_content_lines then
    log:warn("[Block Anchor Enhanced] File too large (%d lines), limiting to %d", #content_lines, max_content_lines)
    content_lines = vim.list_slice(content_lines, 1, max_content_lines)
  end

  if #search_lines > max_search_lines then
    log:warn("[Block Anchor Enhanced] Search block too large (%d lines), aborting", #search_lines)
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

              local line_similarity = calculate_line_similarity(content_line, search_line)
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
          if total_confidence >= 0.7 then
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
          if anchor_pairs_checked >= max_anchor_pairs then
            log:warn("[Block Anchor Enhanced] Checked %d anchor pairs, terminating early", anchor_pairs_checked)
            break
          end
        end
      end
    end
  end

  log:debug("Inser_edit_into_file Strategies] Block anchor found %d matches", #matches)
  return matches
end

---Main strategy executor - tries strategies in order until confident match found
---@param content string The content to search within
---@param old_text string The text to find the best match for
---@param replace_all? boolean Whether this is a replaceAll operation
---@return table Result containing success status, matches, and strategy information
function M.find_best_match(content, old_text, replace_all)
  replace_all = replace_all or false
  -- Early validation to prevent processing huge inputs
  if #content > 2000000 then -- 2MB limit
    log:warn("[Edit Tool Exp Strategies] Content too large (%d bytes), aborting", #content)
    return {
      success = false,
      error = "File too large for edit tool exp matching strategies",
      attempted_strategies = {},
    }
  end

  if #old_text > 50000 then -- 50KB limit for search text
    log:warn("Inser_edit_into_file Strategies] Search text too large (%d bytes), aborting", #old_text)
    return {
      success = false,
      error = "Search text too large for edit tool exp matching strategies",
      attempted_strategies = {},
    }
  end

  local all_strategies = {
    { name = "exact_match", func = M.exact_match, min_confidence = 1.0 },
    { name = "substring_exact_match", func = M.substring_exact_match, min_confidence = 1.0, only_replace_all = true },
    { name = "whitespace_normalized", func = M.whitespace_normalized, min_confidence = 0.95 },
    { name = "punctuation_normalized", func = M.punctuation_normalized, min_confidence = 0.93 },
    { name = "position_markers", func = M.position_markers, min_confidence = 1.0 },
    { name = "trimmed_lines", func = M.trimmed_lines, min_confidence = 0.8 },
    { name = "block_anchor", func = M.block_anchor, min_confidence = 0.6 },
  }

  -- Keep track of best ambiguous match as fallback
  local best_ambiguous_result = nil

  for i, strategy in ipairs(all_strategies) do
    -- Skip substring_exact_match if not replaceAll
    if strategy.only_replace_all and not replace_all then
      log:debug("Inser_edit_into_file Strategies] Skipping %s (only for replaceAll)", strategy.name)
      goto continue
    end

    log:debug("Inser_edit_into_file Strategies] Trying strategy: %s", strategy.name)

    -- Add timeout protection for each strategy
    local start_time = vim.loop.hrtime()
    local matches = strategy.func(content, old_text)
    local elapsed_ms = (vim.loop.hrtime() - start_time) / 1000000

    log:debug("Inser_edit_into_file Strategies] Strategy %s took %.2fms", strategy.name, elapsed_ms)

    if elapsed_ms > 5000 then -- 5 second warning
      log:warn("Inser_edit_into_file Strategies] Strategy %s took unusually long: %.2fms", strategy.name, elapsed_ms)
    end

    -- Filter by confidence threshold
    local good_matches = vim.tbl_filter(function(match)
      return match.confidence >= strategy.min_confidence
    end, matches)

    if #good_matches > 0 then
      log:debug("Inser_edit_into_file Strategies] Strategy %s found %d matches", strategy.name, #good_matches)

      -- Check if this is the last strategy
      local is_last_strategy = (i == #all_strategies)

      -- Try to select best match - if ambiguous, continue to next strategy
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
          -- Last strategy and ambiguous - use best match as fallback
          table.sort(good_matches, function(a, b)
            if math.abs(a.confidence - b.confidence) > 0.01 then
              return a.confidence > b.confidence
            end
            return (a.start_line or 0) < (b.start_line or 0)
          end)
          -- Return only the best match (first after sorting) to avoid re-selection ambiguity
          return {
            success = true,
            matches = { good_matches[1] },
            strategy_used = strategy.name,
            total_attempts = vim.tbl_keys(all_strategies),
            fallback_used = true,
          }
        else
          goto continue
        end
      end

      if selection_result.success then
        log:debug("Inser_edit_into_file Strategies] Strategy %s succeeded with confident match", strategy.name)
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
    table.sort(best_ambiguous_result.matches, function(a, b)
      if math.abs(a.confidence - b.confidence) > 0.01 then
        return a.confidence > b.confidence
      end
      return (a.start_line or 0) < (b.start_line or 0)
    end)
    -- Return only the best match (first after sorting) to avoid re-selection ambiguity
    return {
      success = true,
      matches = { best_ambiguous_result.matches[1] },
      strategy_used = best_ambiguous_result.strategy_used,
      total_attempts = vim.tbl_keys(all_strategies),
      fallback_used = true,
    }
  end

  log:debug("Inser_edit_into_file Strategies] All strategies failed")
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
    if math.abs(a.confidence - b.confidence) > 0.1 then
      return a.confidence > b.confidence
    end
    -- Tie-breaker: prefer earlier occurrence
    return (a.start_line or 0) < (b.start_line or 0)
  end)

  local best_match = matches[1]
  local second_best = matches[2]

  -- Check if matches are too ambiguous - signal to try next strategy
  if math.abs(best_match.confidence - second_best.confidence) < 0.15 then
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
